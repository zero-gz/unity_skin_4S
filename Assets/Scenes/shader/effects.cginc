#ifndef EFFECTS_INCLUDE
#define EFFECTS_INCLUDE

#include "common.cginc"

//  TA技法
// effect color_tint
/*
sampler2D _id_tex;
uniform float4 _color_tint1;
uniform float4 _color_tint2;
uniform float4 _color_tint3;

void effect_color_tint(v2f i, inout MaterialVars mtl, inout LightingVars data)
{
	float4 mask_value = tex2D(_id_tex, i.uv);
	float gray_value = dot(mtl.albedo, float3(0.299f, 0.587f, 0.114f));
	float3 tint1_result = lerp(mtl.albedo, _color_tint1.rgb*_color_tint1.a*gray_value, float3(mask_value.r, mask_value.r, mask_value.r));
	float3 tint2_result = lerp(tint1_result, _color_tint2.rgb*_color_tint2.a*gray_value, float3(mask_value.g, mask_value.g, mask_value.g));
	float3 tint3_result = lerp(tint2_result, _color_tint3.rgb*_color_tint3.a*gray_value, float3(mask_value.b, mask_value.b, mask_value.b));

	mtl.albedo = tint3_result;
}
*/


// effect emissive
/*
sampler2D _emissive_mask_map;

void effect_emissive(v2f i, inout MaterialVars mtl, inout LightingVars data)
{
	float4 mask_value = tex2D(_emissive_mask_map, i.uv);
	mtl.emissive = _emissive*mask_value.r;
}
*/


// effect fresnel
/*
uniform float4 _fresnel_color;
uniform float _fresnel_scale;
uniform float _fresnel_bias;
uniform float _fresnel_power;

// schlick近似公式
float fresnel_standard_node(float fresnel_scale, float3 V, float3 N)
{
	return fresnel_scale + (1.0 - fresnel_scale)*pow((1.0 - dot(V, N)), 5.0);
}

// Empricial近似公式， 这个控制变量更多，可以把效果做的更柔和一点
float fresnel_simulate_node(float fresnel_bias, float fresnel_scale, float fresnel_power, float3 V, float3 N)
{
	return max(0.0, min(1.0, fresnel_bias + fresnel_scale * pow((1.0 - dot(V, N)), fresnel_power)) );
}

// effect outline color
void effect_fresnel_color(v2f i, inout MaterialVars mtl, inout LightingVars data)
{
	//float fresnel_factor = fresnel_standard_node(_fresnel_scale, data.V, data.N);
	float fresnel_factor = fresnel_simulate_node(_fresnel_bias, _fresnel_scale, _fresnel_power, data.V, data.N);
	mtl.albedo = lerp(mtl.albedo, _fresnel_color.rgb, float3(fresnel_factor, fresnel_factor, fresnel_factor) );
}
*/

/*
// effect energy 
sampler2D _energy_tex;
uniform float4 _energy_tex_ST;
sampler2D _mask_tex;
uniform float _speed_x;
uniform float _speed_y;
uniform float _energy_strength;

// 这种默认的是UV空间的，这种依赖uv空间的东西，主要就是美术展UV的时候有限制
void effect_energy(v2f i, inout MaterialVars mtl, inout LightingVars data)
{
	float2 new_uv = i.uv + float2(_speed_x, _speed_y)*_Time.x;
	new_uv = new_uv * _energy_tex_ST.xy + _energy_tex_ST.zw;
	float3 energy_color = tex2D(_energy_tex, new_uv).rgb;
	float mask_value = tex2D(_mask_tex, i.uv).r;

	mtl.albedo = mtl.albedo + energy_color * mask_value*_energy_strength;
}

uniform float3 _pos_scale;

//来一个世界空间的,x,y映射，这里有个技巧，就是不使用bounding_box作除法转到0-1范围，直接拿一个 pos_scale就可以了，这个效果可能不太可控，主要是那个scale不太好控制
void effect_energy_model_space(v2f i, inout MaterialVars mtl, inout LightingVars data)
{
	float3 now_pos = i.world_pos*_pos_scale.xyz + float3(_speed_x, _speed_y, 0.0)*_Time.x;
	float2 new_uv = now_pos.xy;

	float3 energy_color = tex2D(_energy_tex, new_uv).rgb;
	float mask_value = tex2D(_mask_tex, i.uv).r;

	mtl.albedo = mtl.albedo + energy_color * mask_value*_energy_strength;
}
*/

/*
sampler2D _bump_tex;
uniform float _bump_scale;
float4 _bump_tex_size;

// bump贴图
void effect_bump(v2f i, inout MaterialVars mtl, inout LightingVars data)
{
	float2 tex_size = float2(1.0f, 1.0f) / _bump_tex_size.xy;

	float2 uv_left = i.uv - float2(tex_size.x, 0.0);
	float2 uv_right = i.uv + float2(tex_size.x, 0.0);

	float2 uv_bottom = i.uv - float2(0.0, tex_size.y);
	float2 uv_top = i.uv + float2(0.0, tex_size.y);

	float delta_x = tex2D(_bump_tex, uv_left).r - tex2D(_bump_tex, uv_right).r;
	float delta_y = tex2D(_bump_tex, uv_bottom).r - tex2D(_bump_tex, uv_top).r;

	mtl.normal = normalize(float3(delta_x*_bump_scale, delta_y*_bump_scale, 1.0) );
}
*/

/*
sampler2D _distortion_tex;
uniform float4 _distortion_tex_ST;
uniform float2 _speeds;
uniform float _distortion_strength;

// 扰动UV贴图
void effect_distortion(v2f i, inout MaterialVars mtl, inout LightingVars data)
{
	float2 aim_uv = i.uv*_distortion_tex_ST.xy + _speeds *_Time.x + _distortion_tex_ST.zw;
	float4 distortion_value = tex2D(_distortion_tex, aim_uv);
	//主要是这里，需要把相应的范围转换到 -1~1范围内
	distortion_value = distortion_value * 2.0 - 1.0;

	float2 new_uv = i.uv + distortion_value.xy * _distortion_strength;
	mtl.albedo = tex2D(_albedo_tex, new_uv).rgb;
}
*/

sampler2D _dissolved_tex;
uniform float _alpha_ref;
uniform float _alpha_width;
uniform float4 _highlight_color;

// 溶解贴图
void effect_dissovle(v2f i, inout MaterialVars mtl, inout LightingVars data)
{
	float dissolved_alpha = tex2D(_dissolved_tex, i.uv).r;

	float diff_alpha = dissolved_alpha - _alpha_ref;

	if (diff_alpha < 0.0f)
		discard;

	if (diff_alpha <= _alpha_width)
		mtl.emissive = _highlight_color.rgb;
}

// 混合多项material  这个感觉在UE中做实验会比较方便一些

#endif