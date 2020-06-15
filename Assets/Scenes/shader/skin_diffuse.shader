Shader "skin_4s/skin_diffuse"
{
	Properties
	{
		_albedo_tex ("albedo texture", 2D) = "white" {}
		_normal_tex ("normal texture", 2D) = "bump"{}
		_mix_tex ("mix texture (R metallic, G roughness)", 2D) = "black" {}
		[HDR]_emissive("Emissive", Color) = (0.0, 0.0, 0.0, 0.0)
		_translucency_scale("translucency scale", Range(0, 2)) = 0.0
		_translucency_intensity("_translucency_intensity", Range(0, 2)) = 1.0
	}
		SubShader
		{
			// 这里的tags要这么写，不然阴影会有问题
			Tags { "RenderType" = "Opaque" "Queue" = "Geometry"}
			LOD 100
			Cull Back
			ZWrite On
			Stencil{
				Ref 5
				comp always
				pass replace
			}

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

			float4x4 S_LightViewProjector;
			float _translucency_scale;
			float _translucency_intensity;
			sampler shadowmap_rt;
			
			#include "UnityCG.cginc"
			#include "Lighting.cginc"
			#include "AutoLight.cginc"

			#include "common.cginc"

			v2f vert (appdata v)
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
				float4 albedo_color =  tex2D(_albedo_tex, i.uv);
				mtl.albedo = albedo_color.rgb;

				float3 normal_color = tex2D(_normal_tex, i.uv).rgb;
				mtl.normal = normal_color*2.0 - 1.0;
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
				data.f0 = lerp(float3(0.04, 0.04, 0.04), mtl.albedo, mtl.metallic);
				data.roughness = mtl.roughness;
				data.metallic = mtl.metallic;
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

			float3 TSM(LightingVars data)
			{
				float3 worldPosition = data.world_pos;
				float3 worldNormal = data.N;
				float3 light = data.L;

				float scale = 8.25f*sqrt((1.0f - _translucency_scale));// 8.25f * (1.0f - translucency) / _SSSScale;
				float4 shrinkedPos = float4(worldPosition - 0.005 * worldNormal, 1.0);
				//float4 shrinkedPos = float4(worldPosition, 1.0);
				float4 shadowPosition = mul(S_LightViewProjector, shrinkedPos);
				float2 shadow_uv = shadowPosition.xy / shadowPosition.w;
				shadow_uv = shadow_uv * 0.5f + float2(0.5f, 0.5f);
				float d1 = tex2D(shadowmap_rt, shadow_uv).r; // 'd1' has a range of 0..1
				float d2 = -shadowPosition.z/shadowPosition.w; // 'd2' has a range of 0..'lightFarPlane'
				float d = scale * abs(d1 - d2);
				float dd = -d * d;
				float3 profile = float3(0.233, 0.455, 0.649) * exp(dd / 0.0064) +
					float3(0.1, 0.336, 0.344) * exp(dd / 0.0484) +
					float3(0.118, 0.198, 0.0)   * exp(dd / 0.187) +
					float3(0.113, 0.007, 0.007) * exp(dd / 0.567) +
					float3(0.358, 0.004, 0.0)   * exp(dd / 1.99) +
					float3(0.078, 0.0, 0.0)   * exp(dd / 7.41);
				return profile * saturate(0.3 + dot(light, -worldNormal))*pow(_translucency_intensity, 3.0);
				//return float3(d1, d1, d1);
			}

			float3 Diffuse_Lambert(float3 DiffuseColor)
			{
				return DiffuseColor * (1 / PI);
			}

			LightingResult skin_4s_lighting(LightingVars data)
			{
				LightingResult result;

				float NoL = max(dot(data.N, data.L), 0.0);
				// unity的问题，乘以了pi
				result.lighting_diffuse = (data.light_color*NoL) * Diffuse_Lambert(data.diffuse_color)*PI;
				result.lighting_specular = float3(0.0, 0.0, 0.0);
				result.lighting_scatter = float3(0.0, 0.0, 0.0);
				return result;
			}

			LightingResult direct_lighting(LightingVars data)
			{
				return skin_4s_lighting(data);
			}

			// --------------------------------------------------------------------------------------

			fixed4 frag (v2f i) : SV_Target
			//fixed4 frag(v2f i) : SV_Target
			{
				MaterialVars mtl = gen_material_vars(i);
				LightingVars data = gen_lighting_vars(i, mtl);

				data = gen_lighting_vars(i, mtl);

				// lighting part
				//LightingResult dir_result = direct_blinnphone_lighting(data);
				LightingResult dir_result = direct_lighting(data);
				
				float3 translucency_color = TSM(data);
				fixed3 final_color = dir_result.lighting_diffuse*data.shadow + translucency_color;

				//GI的处理
				/*
				LightingResult gi_result = gi_lighting(data);

				#ifndef _LIGHTING_TYPE_HAIR_UE
					final_color = final_color + (gi_result.lighting_diffuse + gi_result.lighting_specular)*data.occlusion + mtl.emissive;
					depth = data.pos.z/data.pos.w;
				#else
					float4 ue_hair_data = tex2D(_ue_hair_tex, i.uv);
					float2 screen_pos = i.screen_pos.xy / i.screen_pos.w;
					Unity_Dither(ue_hair_data.a - _hair_clip_alpha, screen_pos);					
					depth = saturate( data.pos.z/data.pos.w + ue_hair_data.r*_hair_depth_unit);
				#endif
				*/
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
