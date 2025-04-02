Shader "NPR/Toon"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" { }
        [HDR]
        _AmbientColor ("Ambient Color", Color) = (0.4, 0.4, 0.4, 1)
        [HDR]
        _SpecularColor ("Specular Color", Color) = (0.9, 0.9, 0.9, 1)
        _Glossiness ("Glossiness", Float) = 32
        [HDR]
        _RimColor ("Rim Color", Color) = (1, 1, 1, 1)
        _RimAmount ("Rim Amount", Range(0, 1)) = 0.716
        _RimThreshold ("Rim Threshold", Range(0, 1)) = 0.5
    }
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" "RenderType" = "Opaque" }
        LOD 100

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                half3 normal : NORMAL;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                half3 worldPos : TEXCOORD1;
                half3 worldViewDir : TEXCOORD2;
                half3 worldNormal : TEXCOORD3;
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                half4 _AmbientColor;
                half4 _SpecularColor;
                half _Glossiness;
                half4 _RimColor;
                half _RimAmount;
                half _RimThreshold;
            CBUFFER_END

            SAMPLER(sampler_MainTex);
            TEXTURE2D(_MainTex);

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.worldPos = TransformObjectToWorld(v.vertex.xyz);
                o.worldNormal = TransformObjectToWorldNormal(v.normal);
                o.worldViewDir = _WorldSpaceCameraPos.xyz - o.worldPos;
                return o;
            }

            half4 frag(v2f i) : SV_Target
            {
                half3 normal = normalize(i.worldNormal);
                half3 viewDir = normalize(i.worldViewDir);
                half3 worldLightDir = normalize(_MainLightPosition.xyz);
                half NdotL = dot(normal, worldLightDir);
                float4 col = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);

                // 漫反射
                float lightIntensity = smoothstep(0.0, 0.1, NdotL);
                float4 light = lightIntensity * _MainLightColor;

                // 高光
                float3 halfDir = normalize(worldLightDir + viewDir);
                float NdotH = dot(normal, halfDir);
                float specularIntensity = pow(NdotH * lightIntensity, _Glossiness * _Glossiness);
                specularIntensity = smoothstep(0.005, 0.01, specularIntensity);
                float4 specular = specularIntensity * _SpecularColor;

                // 边缘光
                float rimDot = 1.0 - saturate(dot(viewDir, normal)); // 法线与视线垂直的地方边缘光强度最强
                float rimIntensity = rimDot * pow(NdotL, _RimThreshold); // 边缘光强度
                rimIntensity = smoothstep(_RimAmount - 0.01, _RimAmount + 0.01, rimIntensity);
                float4 rim = _RimColor * rimIntensity;

                return (light + specular + rim + _AmbientColor) * col; // 最终颜色(漫反射 + 高光 + 边缘光 + 环境光)

            }
            ENDHLSL
        }
    }
}
