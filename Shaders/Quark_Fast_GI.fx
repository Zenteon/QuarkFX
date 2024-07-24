//========================================================================
/*
	Copyright © Daniel Oren-Ibarra - 2024
	All Rights Reserved.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND
	EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
	MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
	IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
	CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
	TORT OR OTHERWISE,ARISING FROM, OUT OF OR IN CONNECTION WITH THE
	SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
	
	
	======================================================================	
	Quark: TurboGI - Authored by Daniel Oren-Ibarra "Zenteon"
	
	Discord: https://discord.gg/PpbcqJJs6h
	Patreon: https://patreon.com/Zenteon


*/
//========================================================================

#include "ReShade.fxh"
#include "ContinuityCommon.fxh"
#define HDR 1.01

uniform float INTENSITY <
	ui_min = 0.0;
	ui_max = 10.0;
	ui_type = "drag";
	ui_label = "GI Intensity";
> = 5.0;

uniform float AO_INTENSITY <
	ui_min = 0.0;
	ui_max = 1.0;
	ui_type = "drag";
	ui_label = "AO Intensity";
> = 0.8;

uniform float RAY_LENGTH <
	ui_min = 0.5;
	ui_max = 1.0;
	ui_type = "drag";
	ui_label = "Ray Length";
> = 1.0;

uniform float DROPOFF <
	ui_type = "drag";
	ui_label = "Depth Dropoff";
	ui_min = 0.0;
	ui_max = 1.0;
> = 0.3;

uniform int DEBUG <
	ui_type = "combo";
	ui_items = "None\0GI\0";
> = 0;

uniform int FRAME_COUNT <
	source = "framecount";>;

	//============================================================================
	//Bullshit
	//============================================================================

texture ShitMotionVectors { DIVRES(3); };
sampler MVSam0 { Texture = ShitMotionVectors; };	
	
namespace TurboGI {

	texture NormalTex { DIVRES(2); Format = RGBA8; MipLevels = 5; };
	texture NorDivTex { DIVRES(6); Format = RGBA8; MipLevels = 5; };
	texture DepDivTex { DIVRES(6); Format = R16; MipLevels = 5; };
	texture LumDivTex { DIVRES(6); Format = RGBA16F; MipLevels = 5; };
	
	sampler Normal { Texture = NormalTex; WRAPMODE(BORDER); };
	sampler NorDiv { Texture = NorDivTex; WRAPMODE(BORDER); };
	sampler DepDiv { Texture = DepDivTex; WRAPMODE(BORDER); };
	sampler LumDiv { Texture = LumDivTex; WRAPMODE(BORDER); };
	
	texture GITex { DIVRES(3); Format = RGBA8; MipLevels = 2; };
	sampler GISam { Texture = GITex; };
	
	texture CurTex{ DIVRES(3); Format = RGBA8; MipLevels = 2; };
	sampler CurSam { Texture = CurTex; };
	
	texture PreGITex { DIVRES(3); Format = RGBA8; MipLevels = 2; };
	sampler PreGISam { Texture = PreGITex; };
	
	texture PreDepTex { DIVRES(3); Format = R16; };
	sampler PreDep { Texture = PreDepTex; };
	
	texture DenTex0 { DIVRES(3); Format = RGBA8; };
	texture DenTex1 { DIVRES(2); Format = RGBA8; };
	
	sampler DenSam0 { Texture = DenTex0; };
	sampler DenSam1 { Texture = DenTex1; };
	
	//============================================================================
	//Functions
	//============================================================================
	
	float IGN(float2 xy)
	{
	    float3 conVr = float3(0.06711056, 0.00583715, 52.9829189);
	    return frac( conVr.z * frac(dot(xy,conVr.xy)) );
	}
	
	float4 hash42(float2 inp)
	{
		uint pg = uint(RES.x * inp.y + inp.x);
		uint state = pg * 747796405u + 2891336453u;
		uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
		uint4 RGBA = 0xFFu & word >> uint4(0,8,16,24); 
		return float4(RGBA) / float(0xFFu);
	}
	
	float4 psuedoB(float2 xy)
	{
	    float4 noise = hash42(xy);
	    float4 bl;
	    for(int i; i < 9; i++)
	    {
	        float2 offset = float2(floor(float(i) / 3.0), i % 3) - 1.0;
	        bl += hash42(xy + offset);
	    }
	         
	    return noise - (bl / 9.0) + 0.5;
	}
	
	
	//============================================================================
	//Passes
	//============================================================================
	
	
	float4 GenNormals(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		float2 fp = 1.0 / RES;
		float3 pos = NorEyePos(xy);
		float3 dx = pos - NorEyePos(xy + float2(fp.x, 0.0));
		float3 dy = pos - NorEyePos(xy + float2(0.0, fp.y));
		return float4(0.5 + 0.5 * normalize(cross(dy, dx)), 1.0);
	}
	
	void FillSampleTex(in float4 vpos : SV_Position, in float2 xy : TexCoord, out float dep : SV_Target0, out float4 nor : SV_Target1, out float4 lum : SV_Target2)
	{
		dep = GetDepth(xy);
		float2 hp = 2.0 / RES;
		nor =  tex2Dlod(Normal, float4( xy + float2(hp.x, hp.y), 0, 2) );
		nor += tex2Dlod(Normal, float4( xy + float2(hp.x, -hp.y), 0, 2) );
		nor += tex2Dlod(Normal, float4( xy + float2(-hp.x, hp.y), 0, 2) );
		nor += tex2Dlod(Normal, float4( xy + float2(-hp.x, -hp.y), 0, 2) );
		nor *= 0.25;
		
		float3 input = GetBackBuffer(xy);
		float3 GI = 5.0 * pow(input, 2.2) * tex2D(GISam, xy).rgb;
		lum = float4(IReinJ(input, HDR, 0, 0) + GI, 1.0);
		if(dep == 1.0) lum = float4(0.0.xxx, 1.0);
	}
	
	//============================================================================
	//GI
	//============================================================================
	#define FRAME_MOD (3.0 * (FRAME_COUNT % 32 + 1))
	
	
	float4 CalcGI(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		float3 surfN = 2f * tex2D(Normal, xy).xyz - 1f;
		
		
		float3 posV  = NorEyePos(xy);
		float3 vieV  = normalize(posV);
		if(posV.z == FARPLANE) discard;	
	
		float dir = 6.28 * IGN(vpos.xy);
		float3 acc;
		float aoAcc;
		for(int ii; ii < 3; ii++)
		{
			dir += 2.093;
			float2 off = float2(cos(dir), sin(dir));
			
			float dirW = clamp(1.0 / (1.0 + dot(normalize(surfN.xy + off), off)), 0.1, 3.0); //Debias weight			
			
			off = normalize(surfN.xy + off) / RES;
			
			float rnd = IGN((FRAME_MOD + vpos.xy) % RES) + 0.5;
			
			float maxDot;
			
			uint bfd;
			
			for(int i = 1; i <= 6; i++) 
			{
				float lod = floor(0.5 * i);
				float2 sampXY = xy + rnd * RAY_LENGTH * 20.0 * pow(i, 1.5) * off;
				if(sampXY.x > 1.0 || sampXY.x < 0.0) break;
				if(sampXY.y > 1.0 || sampXY.y < 0.0) break;
				
				float  sampD = tex2Dlod(DepDiv, float4(sampXY, 0, lod)).x + 0.0002;
				float3 sampN = 2f * tex2Dlod(NorDiv, float4(sampXY, 0, lod)).xyz - 1f;
				float3 sampL = tex2Dlod(LumDiv, float4(sampXY, 0, lod)).rgb;
				
				float3 posR  = GetEyePos(sampXY, sampD);
				maxDot = max(maxDot, dot(-surfN, normalize(posR - posV)));
				
				
				float  trns  = max(CalcTransfer(posV, surfN, posR, sampN, 20.0, 1.0), 0.0);
				acc += 1.25 * sampL * trns;
			}
			aoAcc += dirW * (maxDot) / 3.0;
		}
		return float4(ReinJ(acc, HDR, 0, 0), aoAcc);
	
	}
	
	//============================================================================
	//Denoise
	//============================================================================
	
	float4 Denoise0(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		float  surfD = GetDepth(xy);
		if(surfD == 1.0) discard;
		float3 surfN = 2f * tex2D(Normal, xy).xyz - 1f;
		float  adpThrsh = 0.2 + saturate(dot(surfN, float3(0.0, 0.0, -1.0)));//Adaptive depth threshold
		
		
		float4 acc = tex2D(CurSam, xy);
		float accW = 1.0;
		
		for(int i = -3; i <= 3; i++) for(int ii = -3; ii <= 3; ii++)
		{
			float2 offset = 4.0 * float2(i, ii) / RES;
			
			float4 sampC = tex2Dlod(CurSam, float4(xy + offset, 0, 0));
			float  sampD = tex2D(DepDiv, xy + offset).x;
			//float3 sampN = 2f * tex2D(NorDiv, xy + offset).xyz - 1f;
			
			float  wN = 1.0;//pow(saturate(dot(surfN, sampN)), 1.0);
			float  wD = exp(-distance(surfD, sampD) * (50.0 / surfD) * adpThrsh);
			acc += wD * wN * sampC;
			accW += wD * wN;
		}
		return acc / accW;
	}
	
	float4 Denoise1(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		float  surfD = GetDepth(xy);
		if(surfD == 1.0) discard;
		float3 surfN = 2f * tex2D(Normal, xy).xyz - 1f;
		float  adpThrsh = 0.2 + saturate(dot(surfN, float3(0.0, 0.0, -1.0)));//Adaptive depth threshold
		
		
		float4 acc = tex2D(DenSam0, xy);
		float accW = 1.0;
		
		for(int i = -1; i <= 1; i++) for(int ii = -1; ii <= 1; ii++)
		{
			float2 offset = 4.0 * float2(i, ii) / RES;
			
			float4 sampC = tex2Dlod(DenSam0, float4(xy + offset, 0, 0));
			float  sampD = tex2D(DepDiv, xy + offset).x;
			//float3 sampN = 2f * tex2D(NorDiv, xy + offset).xyz - 1f;
			float  wN = 1.0;//pow(saturate(dot(surfN, sampN)), 1.0);
			float  wD = exp(-distance(surfD, sampD) * (200.0 / surfD) * adpThrsh);
			acc += wD * wN * sampC;
			accW += wD * wN;
		}
		return acc / accW;
	}
	
	float4 CurFrm(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		float2 MV = tex2D(MVSam0, xy).xy;
		float4 pre = tex2D(PreGISam, xy + MV);
		float4 cur = tex2D(GISam, xy);
		float CD = GetDepth(xy);
		float PD = tex2D(PreDep, xy + MV).r;
		
		float DEG = min(saturate(pow(abs(PD / CD), 20.0) + 0.0), saturate(pow(abs(CD / PD), 10.0) + 0.0));
		
		return lerp(cur, pre, DEG * 0.8);
	}
	
	float4 CopyGI(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		return tex2D(CurSam, xy);
	}
	
	float CopyDepth(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		return tex2D(DepDiv, xy).r;
	}
	
	//============================================================================
	//Blending
	//============================================================================
	
	float CalcFog(float d, float den)
	{
		float2 se = float2(0.0, 0.5 - 0.5 * DROPOFF);
		se.y = max(se.y, se.x + 0.001);
		
		d = saturate(1.0 / (se.y) * d - se.x);
	
		float f = 1.0 - 1.0 / exp(pow(d * den, 2.0));
		
		return saturate(f);
	}
	
	float3 Blend(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		
		float3 input = tex2D(ReShade::BackBuffer, xy).rgb;
		float3 prein = input;
		
		//depth thing
		float depth = GetDepth(xy);
		if(depth == 1.0) return lerp(input, 0.5, DEBUG);
		float lerpVal = CalcFog(depth, 1.0);
		
		//AO
		float4 GI = tex2D(DenSam1, xy);// * pow(input, 2.2);
		float AO = GI.a;
		AO = lerp(1.0, AO, 0.95 * AO_INTENSITY);
		
		//Debug out
		if(DEBUG) return lerp(ReinJ(AO * 0.33 + IReinJ(GI.rgb, HDR, 0, 0) * INTENSITY, HDR, 0, 0), 0.5, lerpVal);
		
		//Fake albedo
		float inGray = prein.r + prein.g + prein.b;
		float3 albedo = pow(2.0 * prein / (1.0 + inGray), 2.2);
		
		//GI blending
		GI.rgb = IReinJ(GI.rgb, HDR, 0, 0);
		GI.rgb *= INTENSITY * albedo;
		input = IReinJ(input, HDR, 0, 0);
		
		
		
		return lerp(ReinJ(AO * input + GI.rgb, HDR, 0, 0), prein, lerpVal);
	
	}
	
	technique TurboGI
	{
		pass { VertexShader = PostProcessVS; PixelShader = GenNormals; RenderTarget = NormalTex; }
		pass { VertexShader = PostProcessVS; PixelShader = FillSampleTex; RenderTarget0 = DepDivTex; RenderTarget1 = NorDivTex; RenderTarget2 = LumDivTex; }
		pass { VertexShader = PostProcessVS; PixelShader = CalcGI; RenderTarget = GITex; }
		
		pass { VertexShader = PostProcessVS; PixelShader = CurFrm; RenderTarget = CurTex; }
		
		pass { VertexShader = PostProcessVS; PixelShader = Denoise0; RenderTarget = DenTex0; }
		pass { VertexShader = PostProcessVS; PixelShader = Denoise1; RenderTarget = DenTex1; }
		
		
		pass { VertexShader = PostProcessVS; PixelShader = CopyGI; RenderTarget = PreGITex; }
		pass { VertexShader = PostProcessVS; PixelShader = CopyDepth; RenderTarget = PreDepTex; }
		
		pass { VertexShader = PostProcessVS; PixelShader = Blend; }
	}
}
