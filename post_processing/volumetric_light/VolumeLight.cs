using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using static UnityEngine.Random;

[System.Serializable, VolumeComponentMenu("Volume Light")]
public class VolumeLightSettings : VolumeComponent, IPostProcessComponent
{
    public ClampedFloatParameter stepTime = new ClampedFloatParameter(8, 1, 64);
    public ClampedFloatParameter intensity = new ClampedFloatParameter(0, 0, 1);

    public ClampedIntParameter loop = new ClampedIntParameter(3, 1, 10);

    // 双边滤波的属性
    public ClampedFloatParameter Space_S = new ClampedFloatParameter(0.3f, 0.1f, 5f);
    public ClampedFloatParameter Space_R = new ClampedFloatParameter(0.3f, 0.1f, 5f);
    public ClampedFloatParameter KernelSize = new ClampedFloatParameter(0.5f, 0.1f, 30f);

    // 实现接口
    public bool IsActive()
    {
        return intensity.value > 0;
    }

    public bool IsTileCompatible()
    {
        return false;
    }
}

public class VolumeLight : ScriptableRendererFeature
{
    [System.Serializable]
    public class Settings
    {
        public RenderPassEvent renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
        public Shader shader;
    }

    public Settings settings = new Settings();

    VolumeLightPass m_pass; // 定义我们创建出Pass


    public override void Create()
    {
        m_pass = new VolumeLightPass(RenderPassEvent.BeforeRenderingPostProcessing, settings.shader);    // 初始化 我们的渲染层级和Shader
    }
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_pass);
    }
}

public class VolumeLightPass : ScriptableRenderPass
{
    static readonly string RenderTag = " Post Effects";                     // 设置渲染标签                                                          // 定义组件类型
    Material material;                                                      // 后处理材质
    VolumeLightSettings settings;

    public VolumeLightPass(RenderPassEvent evt, Shader biltshader)
    {
        renderPassEvent = evt;
        var shader = biltshader;

        if (shader == null)
        {
            Debug.LogError("没有指定Shader");
            return;
        }
        material = CoreUtils.CreateEngineMaterial(biltshader);
    }

    public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
    {
        if (material == null)
        {
            Debug.LogError("材质初始化失败");
            return;
        }

        if (!renderingData.cameraData.postProcessEnabled)
        {
            return;
        }

        var stack = VolumeManager.instance.stack;                          // 传入 volume
        settings = stack.GetComponent<VolumeLightSettings>();                     // 获取到后处理组件

        var cmd = CommandBufferPool.Get(RenderTag);    // 渲染标签

        Render(cmd, ref renderingData);                 // 调用渲染函数

        context.ExecuteCommandBuffer(cmd);              // 执行函数，回收。
        CommandBufferPool.Release(cmd);
    }

    void Render(CommandBuffer cmd, ref RenderingData renderingData)
    {
        RenderTargetIdentifier source = renderingData.cameraData.renderer.cameraColorTargetHandle;                 // 定义RT
        RenderTextureDescriptor inRTDesc = renderingData.cameraData.cameraTargetDescriptor;
        inRTDesc.depthBufferBits = 0;                                                                          // 清除深度

        material.SetFloat("_StepTime", settings.stepTime.value);
        material.SetFloat("_Intensity", settings.intensity.value);

        material.SetFloat("_Space_Sigma", settings.Space_S.value);
        material.SetFloat("_Range_Sigma", settings.Space_R.value);
        material.SetFloat("_KernelSize", settings.KernelSize.value);

        int destination = Shader.PropertyToID("Temp1");
        int blurRT = Shader.PropertyToID("Temp2");

        // 获取一张临时RT
        cmd.GetTemporaryRT(destination, inRTDesc, FilterMode.Bilinear);
        cmd.GetTemporaryRT(blurRT, inRTDesc, FilterMode.Bilinear);

        // 体积光处理
        cmd.Blit(source, destination, material, 0);

        // 多次迭代，实现多次模糊
        for (int i = 0; i < settings.loop.value; i++)
        {
            cmd.Blit(destination, blurRT, material, 1);
            cmd.Blit(blurRT, destination);
        }

        // 最后将结果叠加到原RT上
        cmd.SetGlobalTexture("_FinalTex", source);
        cmd.Blit(destination, blurRT, material, 2);
        cmd.Blit(blurRT, source);

        cmd.ReleaseTemporaryRT(destination);
        cmd.ReleaseTemporaryRT(blurRT);
    }
}