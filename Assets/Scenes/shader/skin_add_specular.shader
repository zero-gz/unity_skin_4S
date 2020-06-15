Shader "skin_4s/skin_add_specular" {
	Properties{
	}

	SubShader{
		ZTest Always
		ZWrite Off
		Cull Off
		Stencil{
			Ref 5
			comp equal
			pass keep
		}

		Pass {
			Name "AddSpecular"
			CGPROGRAM
				#pragma vertex vert
				#pragma fragment frag
				#pragma multi_compile_fwdbase
				#pragma target 3.0
				#pragma enable_d3d11_debug_symbols

				sampler2D _MainTex;
				sampler2D skin_specular_rt;

				struct VertexInput {
					float4 vertex : POSITION;
					float2 uv : TEXCOORD0;
				};
				struct VertexOutput {
					float4 pos : SV_POSITION;
					float2 uv : TEXCOORD0;
				};
				VertexOutput vert(VertexInput v) {
					VertexOutput o;
					o.pos = v.vertex;
					o.uv = v.uv;
					return o;
				}

				float4 frag(VertexOutput i) : SV_TARGET {
					float4 SceneColor = tex2D(_MainTex, i.uv);
					float4 specular_color = tex2D(skin_specular_rt, i.uv);

					float3 result = SceneColor.rgb + specular_color.rgb;
					return float4(result, SceneColor.a);
				}
            ENDCG
        } 
    }
}
