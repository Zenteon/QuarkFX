#pragma once

#define RES float2(BUFFER_WIDTH, BUFFER_HEIGHT)
#define FARPLANE RESHADE_DEPTH_LINEARIZATION_FAR_PLANE
#define ASPECT_RATIO (RES.x/RES.y)

#define FULLTEX Width = RES.x; Height = RES.y
#define HALFTEX Width = 0.5 * RES.x; Height = 0.5 * RES.y
#define QUARTEX Width = 0.25 * RES.x; Height = 0.25 * RES.y
#define WRAPMODE(WTYPE) AddressU = WTYPE; AddressV = WTYPE; AddressW = WTYPE
#define FILTER(FTYPE) MagFilter = FTYPE; MinFilter = FTYPE; MipFilter = FTYPE

#define DIVRES(DIVRES_RIV) Width = BUFFER_WIDTH / DIVRES_RIV; Height = BUFFER_HEIGHT / DIVRES_RIV



namespace Continuity {
	texture NormalTexture { FULLTEX; Format = RG8; MipLevels = 3; };
	texture NorSamTexture { QUARTEX; Format = RG8; MipLevels = 7; };
	texture DepSamTexture { QUARTEX; Format = R16; MipLevels = 7; };
	texture ColorTexture  { FULLTEX; Format = RGBA8;	MipLevels = 1; }; 
	texture DepDerivTex  { FULLTEX; Format = R16F; };
	texture ThickTexture { FULLTEX; Format = R8; MipLevels = 3; };
	//texture ThkSamTexture { QUARTEX; Format = R8; MipLevels = 7; };
	
	sampler NormalBuffer  { Texture = NormalTexture; FILTER(POINT); }; 
	sampler NorSamBuffer  { Texture = NorSamTexture; FILTER(POINT); };
	sampler DepSamBuffer  { Texture = DepSamTexture; FILTER(POINT);  };
	sampler ColorBuffer   { Texture = ColorTexture;  FILTER(POINT); };
	sampler DepDeriv	  { Texture = DepDerivTex; FILTER(POINT); };
	
	sampler ThickBuffer   { Texture = ThickTexture; FILTER(POINT); };
	//sampler ThkSamBuffer  { Texture = ThkSamTexture; };
}

//===================================================================================
//Encoding
//===================================================================================

float2 OctWrap(float2 v)
{
    return (1.0- abs(v.yx)) * (v.xy >= 0.0 ? 1.0 : -1.0);
}
 
float2 NormalEncode(float3 n)
{
	return 0.5 - 0.5 * normalize(n).xy;
}
 
float3 NormalDecode(float2 n)
{
	n = -2f * n + 1f;
	float z = 1.0 - dot(n, n);
	return float3(n.xy, -z);
}

//===================================================================================
//Sampling
//===================================================================================

float GetDepDer(float2 xy)
{
	return tex2Dlod(Continuity::DepDeriv, float4(xy, 0, 0)).x;
}

float3 GetNormal(float2 xy)
{
	float2 n = tex2Dlod(Continuity::NormalBuffer, float4(xy, 0, 0)).xy;
	return NormalDecode(n);	
}

float3 SampleNormal(float2 xy, float l)
{
	float2 n = tex2Dlod(Continuity::NorSamBuffer, float4(xy, 0, l)).xy;
	return NormalDecode(n);	
}

float GetDepth(float2 xy)
{
	return ReShade::GetLinearizedDepth(xy);
}

float SampleDepth(float2 xy, float l)
{
	return tex2Dlod(Continuity::DepSamBuffer, float4(xy, 0, l)).x;
}

float3 GetBackBuffer(float2 xy)
{
	return tex2D(ReShade::BackBuffer, xy).rgb;
}

float3 GetAlbedo(float2 xy)
{
	return tex2D(Continuity::ColorBuffer, xy).rgb;
}

float GetThickness(float2 xy)
{
	return tex2Dlod(Continuity::ThickBuffer, float4(xy, 0, 0)).x;
}

//===================================================================================
//Projections
//===================================================================================

#define FOVR 0.5

float3 GetEyePos(float2 xy, float z)
{
	float  nd	 = z * FARPLANE;
	float3 eyp	= float3((2f * xy - 1f) * nd, nd);
	return eyp * float3(FOVR * ASPECT_RATIO, 1.0, 1.0);
}

float3 GetEyePos(float3 xyz)
{
	float2 xy = xyz.xy; float z = xyz.z;
	float  nd	 = z * FARPLANE;
	float3 eyp	= float3((2f * xy - 1f) * nd, nd);
	return eyp * float3(FOVR * ASPECT_RATIO, 1.0, 1.0);
}

float3 NorEyePos(float2 xy)
{
	float  nd	 = ReShade::GetLinearizedDepth(xy) * FARPLANE;
	float3 eyp	= float3((2f * xy - 1f) * nd, nd);
	return eyp * float3(FOVR * ASPECT_RATIO, 1.0, 1.0);
}

float3 GetScreenPos(float3 xyz)
{
	xyz /= float3(FOVR * ASPECT_RATIO, 1.0, 1.0);
	return float3(0.5 + 0.5 * (xyz.xy / xyz.z), xyz.z / FARPLANE);
}

//===================================================================================
//Functions
//===================================================================================

float GetLuminance( float3 x)
{
	return 0.2126 * x.r + 0.7152 * x.g + 0.0722 * x.b;
}	

float3 ReinJ(float3 x, float HDR_RED, bool bypass, bool forceLinear)
{
	if(bypass) return max( pow(x, 1.0 / (1.0 + 1.2 * forceLinear) ), 0.001);
	float  lum = dot(x, float3(0.2126, 0.7152, 0.0722));
	float3 tx  = x / (x + 1.0);
	return pow(HDR_RED * lerp(x / (lum + 1.0), tx, pow(tx, 0.85) ), 1.0 / 2.2);

}

float3 IReinJ(float3 x, float HDR_RED, bool bypass, bool forceLinear)
{
	if(bypass) return max( pow(x, 1.0 + 1.2 * forceLinear), 0.001);
	x = pow(x, 2.2);
	float  lum = dot(x, float3(0.2126, 0.7152, 0.0722));
	float3 tx  = -x / (x - HDR_RED);
	return lerp(tx, -lum / ((0.5 * x + 0.5 * lum) - HDR_RED), pow(x, 0.85) );

}

float CalcDiffuse(float3 pos0, float3 nor0, float3 pos1, float3 nor1)
{
	float diff0 = saturate(dot(nor0, normalize(pos1 - pos0)) - 0.01);
	
	//Option for backface lighting, looks bad
	float diff1 = abs(clamp((dot(nor1, normalize(pos0 - pos1)) - 0.01), 0.0, 1.0));
	return diff0 * diff1;
}

float CalcTransfer(float3 pos0, float3 nor0, float3 pos1, float3 nor1, float disDiv, float att)
{
	float lumMult = pow(att + length(pos1) / disDiv, 2.0);
	float dist = 1.0 / ( lumMult * pow(att + distance(pos0, pos1) / disDiv, 2.0));
	float lamb = CalcDiffuse(pos0, nor0, pos1, nor1);
	return max(lamb * lumMult * dist, 0.001);
}	


float CalcSpecular(float3 pos0, float3 refl0, float3 pos1, float3 nor1, float power)
{
	float spec0 = saturate(dot(refl0, normalize(pos1 - pos0)) - 0.05);
	spec0 = pow(spec0, power) * (0.5 + 0.5 * power);
	
	float dist = 1.0 / pow(1.0 + distance(pos0, pos1) / 4.0, 2.0 / power );
	//Option for backface lighting, looks bad
	float diff0 = abs(clamp((dot(nor1, normalize(pos0 - pos1)) - 0.2), 0.0, 1.0));
	return max(dist * diff0 * spec0, 0.0001);
}

float CalcSSS(float thk, float3 viewV, float3 surfN, float3 lightV)
{
	#define DISTORT  1.0
	#define POWER	1.0
	#define SCALE	1.0
	#define AMBIENT  0.2
	
	float3 thvLum = lightV + surfN * DISTORT;
	float  thkDot = pow( saturate(dot(viewV, - thvLum)), POWER) * SCALE;
	float sss = (thkDot + AMBIENT) * thk;
	return sss;
}

