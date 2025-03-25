Shader "PostProcessing/VolumeLight"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" { }
        // 步进次数
        _StepTime ("StepTime", Float) = 1
        // 光照强度
        _Intensity ("Intensity", Float) = 1
        // 双边滤波参数
        _KernelSize ("KernelSize", Float) = 1
        _Space_Sigma ("Space_Sigma", Float) = 1
        _Range_Sigma ("Range_Sigma", Float) = 1
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" "RenderPipeline" = "UniversalRenderPipeline" }

        ZWrite Off
        ZTest Always
        Cull Off

        LOD 100

        HLSLINCLUDE
        #define MAIN_LIGHT_CALCULATE_SHADOWS  //定义阴影采样
        #define _MAIN_LIGHT_SHADOWS_CASCADE //启用级联阴影

        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"  //阴影计算库
        #include "Packages/com.unity.render-pipelines.universal/Shaders/PostProcessing/Common.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

        #define random(seed) sin(seed * 641.5467987313875 + 1.943856175)
        #define MAX_RAY_LENGTH 20
        
        CBUFFER_START(UnityPerMaterial)
            float4 _MainTex_ST;
            float4 _MainTex_TexelSize;
            float _StepTime;
            float _Intensity;
            float _MaxDistance;
            float _KernelSize;
            float _Space_Sigma;
            float _Range_Sigma;
        CBUFFER_END

        TEXTURE2D(_MainTex);
        SAMPLER(sampler_MainTex);
        TEXTURE2D(_FinalTex);
        SAMPLER(sampler_FinalTex);

        struct appdata
        {
            float4 vertex : POSITION;
            float2 uv : TEXCOORD0;
        };

        struct v2f
        {
            float2 uv : TEXCOORD0;
            float4 positionHCS : SV_POSITION;
        };

        // 获取世界坐标
        float3 GetTheWorldPos(float3 positionHCS)
        {
            float2 uv = positionHCS.xy / _ScaledScreenParams.xy;

            // Sample the depth from the Camera depth texture.
            #if UNITY_REVERSED_Z
                real depth = SampleSceneDepth(uv);
            #else
                // Adjust Z to match NDC for OpenGL ([-1, 1])
                real depth = lerp(UNITY_NEAR_CLIP_VALUE, 1, SampleSceneDepth(uv));
            #endif

            float3 worldPos = ComputeWorldSpacePosition(uv, depth, UNITY_MATRIX_I_VP);
            return worldPos;
        }

        // 获取光照衰减
        float GetLightAttenuation(float3 position)
        {
            float4 shadowPos = TransformWorldToShadowCoord(position);
            float atten = MainLightRealtimeShadow(shadowPos);
            return atten;
        }
        ENDHLSL

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            v2f vert(appdata v)
            {
                v2f o;
                o.positionHCS = TransformObjectToHClip(v.vertex.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            half4 frag(v2f i) : SV_Target
            {
                float3 worldPos = GetTheWorldPos(i.positionHCS.xyz);
                float3 startPos = _WorldSpaceCameraPos;
                float3 dir = normalize(worldPos - startPos);
                float rayLength = length(worldPos - startPos);
                rayLength = min(rayLength, MAX_RAY_LENGTH);
                
                float3 final = startPos + dir * rayLength;
                
                half3 intensity = 0;
                float2 step = 1.0 / _StepTime;
                step.y *= 0.4;
                float seed = random((_ScreenParams.y * i.uv.y + i.uv.x) * _ScreenParams.x + 0.5);
                for (float i = step.x; i < 1; i += step.x)
                {
                    seed = random(seed);
                    float3 currentPosition = lerp(startPos, final, i + seed * step.y);
                    float atten = GetLightAttenuation(currentPosition) * _Intensity;
                    float3 light = atten;
                    intensity += light;
                }
                intensity /= _StepTime;
                return half4(intensity.rgb, 1);
            }
            ENDHLSL
        }

        // 双边滤波
        Pass
        {
            NAME "BilateralBlur"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            half3 BilateralBlur(float2 uv, float space_sigma, float range_sigma)
            {
                float weight_sum = 0;
                float3 color_sum = 0;
                float3 color_origin = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv).rgb;   //  获取原始颜色
                float3 color = 0;

                // (i,j,k,l)
                for (int i = -_KernelSize; i < _KernelSize; i++)
                {
                    for (int j = -_KernelSize; j < _KernelSize; j++)
                    {
                        //空域高斯
                        float2 varible = uv + float2(i * _MainTex_TexelSize.x, j * _MainTex_TexelSize.y);
                        float space_factor = i * i + j * j;
                        space_factor = (-space_factor) / (2 * space_sigma * space_sigma);
                        float space_weight = 1 / (space_sigma * space_sigma * 2 * PI) * exp(space_factor);     // 空域权重space_weight

                        //值域高斯
                        float3 color_neighbor = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, varible).rgb;
                        float3 color_distance = (color_neighbor - color_origin);
                        float value_factor = color_distance.r * color_distance.r ;
                        value_factor = (-value_factor) / (2 * range_sigma * range_sigma);
                        float value_weight = (1 / (2 * PI * range_sigma)) * exp(value_factor);              // 值域权重value_weight

                        weight_sum += space_weight * value_weight;                                          // 像素点的空域权重的 总和
                        color_sum += color_neighbor * space_weight * value_weight;                          // 计算所有像素点的加权颜色总和
                    }
                }

                if (weight_sum > 0)
                {
                    // 加权颜色总和/权重总和 = 双边模糊后的颜色值
                    color = color_sum / weight_sum;
                }
                return color;
            }


            v2f vert(appdata v)
            {
                v2f o;
                VertexPositionInputs  PositionInputs = GetVertexPositionInputs(v.vertex.xyz);
                o.positionHCS = PositionInputs.positionCS;
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            half4 frag(v2f i) : SV_Target
            {
                half3 color = 0;
                color = BilateralBlur(i.uv, _Space_Sigma, _Range_Sigma);
                return half4(color, 1);
            }

            ENDHLSL
        }

        // 合并两个图像
        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            v2f vert(appdata v)
            {
                v2f o;
                VertexPositionInputs  PositionInputs = GetVertexPositionInputs(v.vertex.xyz);
                o.positionHCS = PositionInputs.positionCS;
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            half4 frag(v2f i) : SV_Target
            {
                half3 oCol = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv).rgb;
                half3 lCol = SAMPLE_TEXTURE2D(_FinalTex, sampler_FinalTex, i.uv).rgb;
                half3 dCol = lCol + oCol;                  //原图和 计算后的图叠加
                return float4(dCol, 1);
            }
            ENDHLSL
        }
    }
}
