Shader "skin_4s/skin_specular"
{
	Properties
	{
		_albedo_tex("albedo texture", 2D) = "white" {}
		_normal_tex("normal texture", 2D) = "bump"{}
		_mix_tex("mix texture (R metallic, G roughness)", 2D) = "black" {}
		[HDR]_emissive("Emissive", Color) = (0.0, 0.0, 0.0, 0.0)
		[KeywordEnum(KSK, PBR)] _SPECULAR("specular mode", Float) = 0
		_specular_intensity("specular intensity", Range(0, 10)) = 1.0
		beckmannTex("beckmannTex", 2D) = "white" {}
	}
		SubShader
		{
			// 这里的tags要这么写，不然阴影会有问题
			Tags { "RenderType" = "Opaque" "Queue" = "Geometry"}
			LOD 100
			Cull Back
			ZWrite On

			Pass
			{
			// 这个ForwardBase非常重要，不加这个， 光照取的结果都会跳变……
			Tags {"LightMode" = "ForwardBase"}
			CGPROGRAM
			#pragma target 5.0
			#pragma vertex vert
			#pragma fragment frag
			#pragma multi_compile LIGHTMAP_OFF LIGHTMAP_ON
			#pragma multi_compile DYNAMICLIGHTMAP_OFF DYNAMICLIGHTMAP_ON
			#pragma multi_compile __ DIRLIGHTMAP_COMBINED
			//#pragma multi_compile __ UNITY_SPECCUBE_BOX_PROJECTION   //奇怪了，不开启这个也能生效，环境球反射……
			#pragma multi_compile __ LIGHTPROBE_SH

			#pragma multi_compile_fwdbase
			#pragma enable_d3d11_debug_symbols
			#pragma multi_compile _SPECULAR_KSK _SPECULAR_PBR

			float _specular_intensity;
			sampler beckmannTex;

			#include "UnityCG.cginc"
			#include "Lighting.cginc"
			#include "AutoLight.cginc"

			#include "common.cginc"

			v2f vert(appdata v)
			{
				v2f o;
				o.pos = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;

				o.world_pos = mul(unity_ObjectToWorld, v.vertex).xyz;
				o.world_normal = mul(v.normal.xyz, (float3x3)unity_WorldToObject);
				o.world_tangent = normalize(mul((float3x3)unity_ObjectToWorld, v.tangent.xyz));
				o.world_binnormal = cross(o.world_normal, o.world_tangent)*v.tangent.w;

				#ifdef LIGHTMAP_ON
					o.lightmap_uv.xy = v.uv1.xy * unity_LightmapST.xy + unity_LightmapST.zw;
					o.lightmap_uv.zw = 0;
				#endif

				#ifdef DYNAMICLIGHTMAP_ON
					o.lightmap_uv.zw = v.uv2.xy * unity_DynamicLightmapST.xy + unity_DynamicLightmapST.zw;
				#endif

				o.screen_pos = ComputeScreenPos(o.pos);
				TRANSFER_SHADOW(o);

				return o;
			}

			MaterialVars gen_material_vars(v2f i)
			{
				MaterialVars mtl;
				float4 albedo_color = tex2D(_albedo_tex, i.uv);
				mtl.albedo = albedo_color.rgb;

				float3 normal_color = tex2D(_normal_tex, i.uv).rgb;
				mtl.normal = normal_color * 2.0 - 1.0;
				mtl.roughness = tex2D(_mix_tex, i.uv).g; //_roughness;
				mtl.metallic = tex2D(_mix_tex, i.uv).r; //_metallic;
				mtl.emissive = _emissive;
				mtl.opacity = albedo_color.a;
				mtl.occlusion = 1.0;

				mtl.sss_color = _sss_color.rgb;

				float4 sss_tex_data = tex2D(_sss_tex, i.uv);
				mtl.thickness = sss_tex_data.r;
				mtl.curvature = sss_tex_data.g;
				return mtl;
			}

			LightingVars gen_lighting_vars(v2f i, MaterialVars mtl)
			{
				LightingVars data;
				data.T = normalize(i.world_tangent);
				data.B = normalize(i.world_binnormal);
				data.N = normalize(normalize(i.world_tangent) * mtl.normal.x + normalize(i.world_binnormal) * mtl.normal.y + normalize(i.world_normal) * mtl.normal.z);

				data.V = normalize(_WorldSpaceCameraPos.xyz - i.world_pos.xyz);
				data.L = normalize(_WorldSpaceLightPos0.xyz);
				data.H = normalize(data.V + data.L);
				data.diffuse_color = mtl.albedo*(1.0 - mtl.metallic);
				data.f0 = float3(1.0f, 1.0f, 1.0f);// lerp(float3(0.04, 0.04, 0.04), mtl.albedo, mtl.metallic);
				data.roughness = mtl.roughness;
				data.metallic = 0.0f;// mtl.metallic;
				data.sss_color = mtl.sss_color;
				data.thickness = mtl.thickness;
				data.curvature = mtl.curvature;
				data.opacity = mtl.opacity;

				data.light_color = _LightColor0.rgb;

				#if defined(LIGHTMAP_ON) || defined(DYNAMICLIGHTMAP_ON)
					data.lightmap_uv = i.lightmap_uv;
				#endif

				data.world_pos = i.world_pos;

				data.occlusion = mtl.occlusion;
				data.shadow = UNITY_SHADOW_ATTENUATION(i, data.world_pos);

				data.base_vars.pos = i.pos;
				data.base_vars.uv0 = i.uv;
				data.pos = i.pos;
				return data;
			}

			// --------------------------------------------------------------------------------------
			float3 Diffuse_Lambert(float3 DiffuseColor)
			{
				return DiffuseColor * (1 / PI);
			}

			// GGX / Trowbridge-Reitz
			// [Walter et al. 2007, "Microfacet models for refraction through rough surfaces"]
			float D_GGX(float a2, float NoH)
			{
				float d = (NoH * a2 - NoH) * NoH + 1;	// 2 mad
				return a2 / (PI*d*d);					// 4 mul, 1 rcp
			}

			// Appoximation of joint Smith term for GGX
			// [Heitz 2014, "Understanding the Masking-Shadowing Function in Microfacet-Based BRDFs"]
			float Vis_SmithJointApprox(float a2, float NoV, float NoL)
			{
				float a = sqrt(a2);
				float Vis_SmithV = NoL * (NoV * (1 - a) + a);
				float Vis_SmithL = NoV * (NoL * (1 - a) + a);
				return 0.5 * rcp(Vis_SmithV + Vis_SmithL);
			}

			// [Schlick 1994, "An Inexpensive BRDF Model for Physically-Based Rendering"]
			float3 F_Schlick(float3 f0, float VoH)
			{
				float Fc = Pow5(1 - VoH);
				return Fc + f0 * (1 - Fc);
			}

			float3 SpecularGGX(LightingVars data)
			{
				float Roughness = data.roughness;
				float NoH = max(saturate(dot(data.N, data.H)), CHAOS);
				float NoL = max(saturate(dot(data.N, data.L)), CHAOS);
				float NoV = max(saturate(dot(data.N, data.V)), CHAOS);
				float VoH = max(saturate(dot(data.V, data.H)), CHAOS);

				// mtl中存放的是 感知线性粗糙度（为了方便美术调整，所以值为实际值的sqrt)				
				float use_roughness = max(Pow2(Roughness), 0.002);
				float a2 = Pow2(use_roughness);
				//float Energy = EnergyNormalization( a2, Context.VoH, AreaLight );
				float Energy = 1.0;

				// Generalized microfacet specular
				float D = D_GGX(a2, NoH) * Energy;
				float Vis = Vis_SmithJointApprox(a2, NoV, NoL);
				float3 F = F_Schlick(data.f0, VoH);

				return (D * Vis) * F;
			}

			float Fresnel(float3 H, float3 view, float f0) {
				float base = 1.0 - dot(view, H);
				float exponential = pow(base, 5.0);
				return exponential + f0 * (1.0 - exponential);
			}

			float SpecularKSK(sampler2D beckmannTex, float3 normal, float3 light, float3 view, float roughness) {
				float3 H = view + light;
				float3 halfn = normalize(H);
				float specularFresnel = 1.0f;

				float ndotl = max(dot(normal, light), 0.0);
				float ndoth = max(dot(normal, halfn), 0.0);
				float factor = tex2D(beckmannTex, float2(ndoth, roughness)).r;
				float ph = pow(2.0 * factor, 10.0);
				float f = lerp(0.25, Fresnel(halfn, view, 0.028), specularFresnel);
				float ksk = max(ph * f / dot(H, H), 0.0);

				return ndotl * ksk;
				//return ph*f;
			}

			// --------------------------------------------------------------------------------

			LightingResult skin_4s_lighting(LightingVars data)
			{
				LightingResult result;

				float NoL = max(dot(data.N, data.L), 0.0);
				// unity的问题，乘以了pi
				result.lighting_diffuse = float3(0.0, 0.0, 0.0);

				#ifdef _SPECULAR_KSK
					float ksk_factor = SpecularKSK(beckmannTex, data.N, data.L, data.V, data.roughness)*_specular_intensity;
					result.lighting_specular = data.light_color*_specular_intensity*PI*ksk_factor;
				#else
					result.lighting_specular = (data.light_color*NoL) * SpecularGGX(data)*PI*_specular_intensity;
				#endif
				result.lighting_scatter = float3(0.0, 0.0, 0.0);
				return result;
			}

			LightingResult direct_lighting(LightingVars data)
			{
				return skin_4s_lighting(data);
			}

			// --------------------------------------------------------------------------------------

			fixed4 frag(v2f i) : SV_Target
				//fixed4 frag(v2f i) : SV_Target
				{
					MaterialVars mtl = gen_material_vars(i);
					LightingVars data = gen_lighting_vars(i, mtl);

					data = gen_lighting_vars(i, mtl);

					// lighting part
					//LightingResult dir_result = direct_blinnphone_lighting(data);
					LightingResult dir_result = direct_lighting(data);
					fixed3 final_color = dir_result.lighting_specular*data.shadow; 
					// sample the texture
					return fixed4(final_color, mtl.opacity);
				}
				ENDCG
			}


			// Pass to render object as a shadow caster

			Pass {
				Tags { "LightMode" = "ShadowCaster" }

				CGPROGRAM

				#pragma vertex vert
				#pragma fragment frag

				#pragma multi_compile_shadowcaster

				#include "UnityCG.cginc"

				struct v2f {
					V2F_SHADOW_CASTER;
					float2 uv:TEXCOORD1;
				};

				v2f vert(appdata_base v) {
					v2f o;

					TRANSFER_SHADOW_CASTER_NORMALOFFSET(o)

					o.uv = v.texcoord;

					return o;
				}

				fixed4 frag(v2f i) : SV_Target {
					SHADOW_CASTER_FRAGMENT(i)
				}
				ENDCG
			}

		}

}
