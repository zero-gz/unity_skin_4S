using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;
using UnityEngine.UI;
using UnityEngine.Rendering;

[RequireComponent(typeof(Camera))]
public class SeparableSubsurfaceScatter : MonoBehaviour {
    [Range(0, 6)]
    public float SubsurfaceScaler = 0.25f;
    public Color SubsurfaceColor = new Color(0.48f, 0.41f, 0.28f);
    public Color SubsurfaceFalloff = new Color(1.0f, 0.37f, 0.3f);

    private Camera m_cam;
    // skin blur part
    private CommandBuffer SkinBlurCommandBuffer;
    private Material SkinBlurEffect;
    private List<Vector4> KernelArray = new List<Vector4>();
    static int Kernel = Shader.PropertyToID("_Kernel");
    static int SSSScaler = Shader.PropertyToID("_SSSScale");
    static int SkinBlurRT_TMP_ID = Shader.PropertyToID("skin_blur_rt_tmp");
    private RenderTexture SkinBlurRT;
    static int SkinBlurRT_ID = Shader.PropertyToID("skin_blur_rt");

    // skin specular part
    public GameObject head_mesh;
    private CommandBuffer SkinSpecularCommandBuffer;
    public Material SkinSpecularEffect;
    [Range(0, 2)]
    public float SpecularIntensity = 1.0f;
    private static int SpecularRT_ID = Shader.PropertyToID("skin_specular_rt");
    private RenderTexture SpecularRT;

    // skin add specular part
    private CommandBuffer SkinAddSpecularCommandBuffer;
    private Material SkinAddSpecularEffect;

    // TSM
    public bool EnableTSM = true;
    [Range(0, 1)]
    public float _translucency_scale = 0.0f;
    [Range(0, 10)]
    public float _translucency_intensity = 1.0f;

    // Use this for initialization
    void Start () {
		
	}
	
	// Update is called once per frame
	void Update () {
		
	}

    private void OnEnable()
    {
        // skin blur part
        m_cam = GetComponent<Camera>();
        SkinBlurCommandBuffer = new CommandBuffer();
        SkinBlurCommandBuffer.name = "4S skin Blur";
        m_cam.AddCommandBuffer(CameraEvent.AfterForwardOpaque, SkinBlurCommandBuffer);
        SkinBlurEffect = new Material(Shader.Find("skin_4s/skin_blur"));
        SkinBlurRT = RenderTexture.GetTemporary(Screen.width, Screen.height, 0, RenderTextureFormat.DefaultHDR);
        SkinBlurRT.name = "skin_blur_rt";

        // skin specular part
        SkinSpecularCommandBuffer = new CommandBuffer();
        SkinSpecularCommandBuffer.name = "4S skin Specular";
        m_cam.AddCommandBuffer(CameraEvent.AfterForwardOpaque, SkinSpecularCommandBuffer);
        SpecularRT = RenderTexture.GetTemporary(Screen.width, Screen.height, 24, RenderTextureFormat.DefaultHDR);
        SpecularRT.name = "skin_specular_rt";

        // skin add specular part
        SkinAddSpecularCommandBuffer = new CommandBuffer();
        SkinAddSpecularCommandBuffer.name = "4S skin Add Specular";
        SkinAddSpecularEffect = new Material(Shader.Find("skin_4s/skin_add_specular"));
        m_cam.AddCommandBuffer(CameraEvent.AfterForwardOpaque, SkinAddSpecularCommandBuffer);

        Shader.SetGlobalTexture(SpecularRT_ID, SpecularRT);
        Shader.SetGlobalTexture(SkinBlurRT_ID, SkinBlurRT);
    }

    private void DrawSkinDiffuse()
    {
        Material mtl = head_mesh.GetComponent<MeshRenderer>().material;
        mtl.SetFloat(Shader.PropertyToID("_translucency_scale"), _translucency_scale);
        float switch_value = EnableTSM?1.0f:0.0f;
        mtl.SetFloat(Shader.PropertyToID("_translucency_intensity"), _translucency_intensity*switch_value);
    }

    private void DrawSkinBlur()
    {
        SkinBlurCommandBuffer.Clear();

        ///SSS Color
        /// 这里不应该normalize
        Vector3 SSSC = new Vector3(SubsurfaceColor.r, SubsurfaceColor.g, SubsurfaceColor.b);
        Vector3 SSSFC = new Vector3(SubsurfaceFalloff.r, SubsurfaceFalloff.g, SubsurfaceFalloff.b);

        SeparableSSS.CalculateKernel(KernelArray, 25, SSSC, SSSFC);
        SkinBlurEffect.SetVectorArray(Kernel, KernelArray);
        SkinBlurEffect.SetFloat(SSSScaler, SubsurfaceScaler);

        SkinBlurCommandBuffer.GetTemporaryRT(SkinBlurRT_TMP_ID, Screen.width, Screen.height, 0, FilterMode.Trilinear, RenderTextureFormat.DefaultHDR);
        SkinBlurCommandBuffer.BlitStencil(BuiltinRenderTextureType.CameraTarget, SkinBlurRT_TMP_ID, BuiltinRenderTextureType.CameraTarget, SkinBlurEffect, 0);
        SkinBlurCommandBuffer.BlitStencil(SkinBlurRT_TMP_ID, SkinBlurRT, BuiltinRenderTextureType.CameraTarget, SkinBlurEffect, 1);
    }

    private void DrawSkinSpecular()
    {
        SkinSpecularCommandBuffer.Clear();
        SkinSpecularCommandBuffer.SetRenderTarget(SpecularRT);
        SkinSpecularCommandBuffer.ClearRenderTarget(true, true, Color.black);

        SkinSpecularEffect.SetFloat(Shader.PropertyToID("_specular_intensity"), SpecularIntensity);
        Mesh mesh = head_mesh.GetComponent<MeshFilter>().mesh;
        SkinSpecularCommandBuffer.DrawMesh(mesh, head_mesh.transform.localToWorldMatrix, SkinSpecularEffect, 0, 0);
    }

    private void DrawSkinAddSpecular()
    {
        SkinAddSpecularCommandBuffer.Clear();
        SkinAddSpecularCommandBuffer.BlitSRT(SkinBlurRT, BuiltinRenderTextureType.CameraTarget, SkinAddSpecularEffect, 0);
    }

    private void OnPreRender()
    {
        DrawSkinDiffuse();
        DrawSkinSpecular();
        DrawSkinBlur();
        DrawSkinAddSpecular();
    }
}
