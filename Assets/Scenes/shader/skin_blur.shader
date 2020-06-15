Shader "skin_4s/skin_blur" {
    Properties {
    }

    SubShader {
        ZTest Always
        ZWrite Off 
        Cull Off
        Stencil{
            Ref 5
            comp equal
            pass keep
        }

		CGINCLUDE
			#include "UnityCG.cginc" 
			#define DistanceToProjectionWindow 5.671281819617709             //1.0 / tan(0.5 * radians(20));
			#define DPTimes300 1701.384545885313                             //DistanceToProjectionWindow * 300
			#define SamplerSteps 25
			uniform sampler2D _CameraDepthTexture;
			float4 _CameraDepthTexture_TexelSize;

			uniform sampler2D _MainTex;
			uniform float4 _MainTex_ST;
			uniform float _SSSScale;
			uniform float4 _Kernel[SamplerSteps];

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

			float4 SSS(float4 SceneColor, float2 UV, float2 SSSIntencity) {
				float SceneDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, UV));
				float BlurLength = DistanceToProjectionWindow / SceneDepth;
				float2 UVOffset = SSSIntencity * BlurLength;
					float4 BlurSceneColor = SceneColor;
				BlurSceneColor.rgb *= _Kernel[0].rgb;

				[loop]
				for (int i = 1; i < SamplerSteps; i++) {
					float2 SSSUV = UV + _Kernel[i].a * UVOffset;
					float4 SSSSceneColor = tex2D(_MainTex, SSSUV);
					float SSSDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, SSSUV)).r;
					float SSSScale = saturate(DPTimes300 * SSSIntencity * abs(SceneDepth - SSSDepth));
					SSSSceneColor.rgb = lerp(SSSSceneColor.rgb, SceneColor.rgb, SSSScale);
					BlurSceneColor.rgb += _Kernel[i].rgb * SSSSceneColor.rgb;
				}
				return BlurSceneColor;
			}
		ENDCG

        Pass {
            Name "XBlur"
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fwdbase
            #pragma target 3.0

            float4 frag(VertexOutput i) : SV_TARGET {
                float4 SceneColor = tex2D(_MainTex, i.uv);
                float SSSIntencity = (_SSSScale * _CameraDepthTexture_TexelSize.x);
                float3 XBlur = SSS(SceneColor, i.uv, float2(SSSIntencity, 0) ).rgb;
                return float4(XBlur, SceneColor.a);
            }
            ENDCG
        } Pass {
            Name "YBlur"
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fwdbase
            #pragma target 3.0

            float4 frag(VertexOutput i) : COLOR {
                float4 SceneColor = tex2D(_MainTex, i.uv);
                float SSSIntencity = (_SSSScale * _CameraDepthTexture_TexelSize.y);
                float3 YBlur = SSS(SceneColor, i.uv, float2(0, SSSIntencity)).rgb;
                return float4(YBlur, SceneColor.a);
            }
            ENDCG
        }
    }
}
