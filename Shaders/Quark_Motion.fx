#include "ReShade.fxh"
#include "QuarkCommon.fxh"

uniform bool DEBUG <
	ui_label = "Debug Flow";
> = 0;

#define PS_INPUTS float4 vpos : SV_Position, float2 xy : TEXCOORD0

//Pass helpers

#define PASS0(iPS) VertexShader = PostProcessVS; PixelShader = iPS
#define PASS1(iPS, oRT) VertexShader = PostProcessVS; PixelShader = iPS; RenderTarget = oRT
#define PASS2(iPS, oRT0, oRT1) VertexShader = PostProcessVS; PixelShader = iPS; RenderTarget0 = oRT0; RenderTarget1 = oRT1
#define PASS3(iPS, oRT0, oRT1, oRT2) VertexShader = PostProcessVS; PixelShader = iPS; RenderTarget0 = oRT0; RenderTarget1 = oRT1; RenderTarget2 = oRT2

texture texMotionVectors { DIVRES(1); Format = RG16F; };
sampler sMV { Texture = texMotionVectors; };
namespace QuarkMotion {
	
	#define FWRAP CLAMP
	#define LFORM RGBA16F
	#define LFILT POINT
	
	texture2D tLevel00 { DIVRES(2); Format = LFORM; };
	sampler2D sLevel00 { Texture = tLevel00; FILTER(LFILT); };
	
	texture2D tLevel0t { DIVRES(4); Format = LFORM; };
	sampler2D sLevel0t { Texture = tLevel0t; FILTER(LFILT); };
	//optical flow
	texture2D tLevel0 { DIVRES(4); Format = LFORM; };
	sampler2D sLevel0 { Texture = tLevel0; FILTER(LFILT); WRAPMODE(FWRAP); };
	texture2D tLevel1 { DIVRES(8); Format = LFORM; };
	sampler2D sLevel1 { Texture = tLevel1; FILTER(LFILT); WRAPMODE(FWRAP); };
	texture2D tLevel2 { DIVRES(16); Format = LFORM; };
	sampler2D sLevel2 { Texture = tLevel2; FILTER(LFILT); WRAPMODE(FWRAP); };
	texture2D tLevel3 { DIVRES(32); Format = LFORM; };
	sampler2D sLevel3 { Texture = tLevel3; FILTER(LFILT); WRAPMODE(FWRAP); };
	texture2D tLevel4 { DIVRES(64); Format = LFORM; };
	sampler2D sLevel4 { Texture = tLevel4; FILTER(LFILT); WRAPMODE(FWRAP); };
	texture2D tLevel5 { DIVRES(128); Format = LFORM; };
	sampler2D sLevel5 { Texture = tLevel5; FILTER(LFILT); WRAPMODE(FWRAP); };
	//current
	texture2D tCG0 { DIVRES(1); Format = R16; };
	sampler2D sCG0 { Texture = tCG0; WRAPMODE(FWRAP); };
	texture2D tCG1 { DIVRES(2); Format = R16; };
	sampler2D sCG1 { Texture = tCG1; WRAPMODE(FWRAP); };
	texture2D tCG2 { DIVRES(4); Format = R16; };
	sampler2D sCG2 { Texture = tCG2; WRAPMODE(FWRAP); };
	texture2D tCG3 { DIVRES(8); Format = R16; };
	sampler2D sCG3 { Texture = tCG3; WRAPMODE(FWRAP); };
	texture2D tCG4 { DIVRES(16); Format = R16; };
	sampler2D sCG4 { Texture = tCG4; WRAPMODE(FWRAP); };
	//previous
	texture2D tPG0 { DIVRES(1); Format = R16; };
	sampler2D sPG0 { Texture = tPG0; WRAPMODE(FWRAP); };
	texture2D tPG1 { DIVRES(2); Format = R16; };
	sampler2D sPG1 { Texture = tPG1; WRAPMODE(FWRAP); };
	texture2D tPG2 { DIVRES(4); Format = R16; };
	sampler2D sPG2 { Texture = tPG2; WRAPMODE(FWRAP); };
	texture2D tPG3 { DIVRES(8); Format = R16; };
	sampler2D sPG3 { Texture = tPG3; WRAPMODE(FWRAP); };
	texture2D tPG4 { DIVRES(16); Format = R16; };
	sampler2D sPG4 { Texture = tPG4; WRAPMODE(FWRAP); };
	
	texture2D tDG0 { DIVRES(1); Format = R16; };
	sampler2D sDG0 { Texture = tDG0; };
	texture2D tDG1 { DIVRES(2); Format = R16; };
	sampler2D sDG1 { Texture = tDG1; };
	texture2D tDG2 { DIVRES(4); Format = R16; };
	sampler2D sDG2 { Texture = tDG2; };
	
		//=======================================================================================
	//Functions
	//=======================================================================================
	
	float IGN(float2 xy)
	{
	    float3 conVr = float3(0.06711056, 0.00583715, 52.9829189);
	    return frac( conVr.z * frac(dot(xy % RES,conVr.xy)) );
	}
	
	#define BLOCK_SIZE 4
	#define BLOCKS_SIZE 2
	
	//=======================================================================================
	//Optical Flow Functions
	//=======================================================================================
	
	float4 tex2DfetchLin(sampler2D tex, float2 vpos)
	{
		float2 s = tex2Dsize(tex);
		return tex2Dlod(tex, float4(vpos / s, 0, 0));
	}
	
	float3 tex2DfetchLinD(sampler2D tex, float2 vpos)
	{
		float2 s = tex2Dsize(tex);
		float2 t = tex2Dlod(tex, float4(vpos / s, 0, 0)).xy;
		float d = GetDepth(vpos / s);
		return float3(t,d);
	}
	
	float GetBlock(sampler2D tex, float2 vpos, float2 offset, float div, inout float Block[BLOCK_SIZE * BLOCK_SIZE] )
	{
		vpos = floor(vpos) * div;
		float acc;
		for(int i; i < BLOCK_SIZE * BLOCK_SIZE; i++)
		{
			int2 np = int2(floor(float(i) / BLOCK_SIZE), i % BLOCK_SIZE);
			float tCol = tex2DfetchLin(tex, vpos + np + offset).r;
			Block[i] = tCol;
			acc += tCol;
		}
		return acc / (BLOCK_SIZE*BLOCK_SIZE);
	}
	
	void GetBlockS(sampler2D tex, float2 vpos, float2 offset, float div, inout float Block[BLOCKS_SIZE * BLOCKS_SIZE] )
	{
		vpos = floor(vpos) * div;
		for(int i; i < BLOCKS_SIZE * BLOCKS_SIZE; i++)
		{
			int2 np = int2(floor(float(i) / BLOCKS_SIZE), i % BLOCKS_SIZE);
			float tCol = tex2DfetchLin(tex, vpos + np + offset).r;
			Block[i] = tCol;
		}
	}
	
	
	float BlockErr(float Block0[BLOCK_SIZE * BLOCK_SIZE], float Block1[BLOCK_SIZE * BLOCK_SIZE])
	{
		float ssd;
		for(int i; i < BLOCK_SIZE*BLOCK_SIZE; i++)
		{
			float t = (Block0[i] - Block1[i]) / (Block0[i] + Block1[i] + 0.001);
			ssd += abs(t);
		}
		
		return ssd * rcp(BLOCK_SIZE*BLOCK_SIZE);
	}
	
	float BlockErrS(float Block0[BLOCKS_SIZE * BLOCKS_SIZE], float Block1[BLOCKS_SIZE * BLOCKS_SIZE])
	{
		float ssd;
		for(int i; i < BLOCKS_SIZE*BLOCKS_SIZE; i++)
		{
			float t = (Block0[i] - Block1[i]) / (Block0[i] + Block1[i] + 0.001);
			ssd += abs(t);
		}
		
		return ssd * rcp(BLOCKS_SIZE*BLOCKS_SIZE);
	}
	
	float3 HueToRGB(float hue)
	{
	    float3 fr = frac(hue.xxx + float3(0.0, -1.0/3.0, 1.0/3.0));
	    float3 s = 3.0 * abs(1.0 - 2.0*fr) - 1.0;
		return s;
		//return 0.5 + 0.5 * sin(12.56 * hue + float3(0.0,1.5707,3.14159));
	}
		
	float3 MVtoRGB( float2 MV )
	{
		float3 col = HueToRGB(atan2(MV.y, MV.x) / 6.28);
		if(isnan(col).x) return 0.5;
		return lerp(0.5, col, saturate(length(MV)));
	
	}
	
	
	float4 CalcMV(sampler2D cur, sampler2D pre, int2 pos, float4 off, int RAD, bool lev0)
	{
		float cBlock[BLOCK_SIZE * BLOCK_SIZE];
		float cenMean = GetBlock(cur, pos, 0.0, 4.0, cBlock);
		
		float sBlock[BLOCK_SIZE * BLOCK_SIZE];
		GetBlock(pre, pos, 0.0, 4.0, sBlock);
		
		float2 MV;
		float2 noff = off.xy;
		
		float Err = BlockErr(cBlock, sBlock);
		
		float cenC = tex2DfetchLin(cur, floor(pos) * 4.0).x;
		
		for(int i = -RAD; i <= RAD; i++) for(int ii = -RAD; ii <= RAD; ii++)
		{
			GetBlock(pre, pos, int2(i, ii) + off.xy, 4.0, sBlock);
			float tErr = BlockErr(cBlock, sBlock);
			[flatten]
			if(tErr < Err)
			{
				Err = tErr;
				MV = float2(i, ii);
			}
			if(Err < 0.001) break;
		}
		
		float cBlockS[BLOCKS_SIZE * BLOCKS_SIZE];
		GetBlockS(cur, pos, 0.0, 4.0, cBlockS);
		
		float sBlockS[BLOCKS_SIZE * BLOCKS_SIZE];
		GetBlockS(pre, pos, 0.0, 4.0, sBlockS);
		
		/*
		off += MV;
		MV = 0.0;
		
		for(int i = -2; i <= 2; i++) for(int ii = -2; ii <= 2; ii++)
		{
			GetBlockS(pre, pos, 0.5 * float2(i, ii) + off, 4.0, sBlockS);
			float tErr = BlockErrS(cBlockS, sBlockS);
			[flatten]
			if(tErr < Err)
			{
				Err = tErr;
				MV = 0.5 * float2(i, ii);
			}
		}
		*/
		Err = cenMean <= exp2(-8) ? 10.0 * Err : Err;
		return float4(MV + off.xy, off.z + Err, 1.0);
	}
	
	
	float4 PrevLayer2(sampler2D tex, int2 vpos, float level, int ITER)
	{
		float3 cen = tex2DfetchLinD(tex, 0.5 * vpos).xyz;
		float2 minm; float2 maxm; float3 t; float td;
		
		float dir = 3.14159 * IGN(vpos + IGNSCROLL * level);
		float2 o;
		
		float2 tcord; float2 txy;
		float w;
		
		for(int i; i < ITER; i++)
		{
			minm = 9999.9; maxm = -9999.9;
			dir += 0.25 * 1.5707;
			o = (1.0 + 0.5 * i) * float2(sin(dir), cos(dir));
			
			txy = vpos + int2(o.y,o.x);
			t = tex2DfetchLinD(tex, 0.5 * txy ).xyz;
			cen.xy += 0.25 * t.xy / (i + 1);
			td += t.z;
			
			minm = min(minm, t.xy); maxm = max(maxm, t.xy);
			txy = vpos - int2(o.y,o.x);
			t = tex2DfetchLinD(tex, 0.5 * txy ).xyz;
			cen.xy += 0.25 * t.xy / (i + 1);
			td += t.z;
			
			minm = min(minm, t.xy); maxm = max(maxm, t.xy);
			cen /= 1.0 + 0.5 * rcp(i + 1);
			float w = exp(-abs(cen.z - 0.5*td) / (cen.z + 0.01));
			cen.xy = lerp(cen.xy, clamp(cen.xy, minm, maxm), 1.0);
			
		}
		
		return float4(2.0 * cen.xy, cen.z, 1.0);
	}
	
	float4 PrevLayer(sampler2D tex, int2 vpos, float level, int ITER)
	{
		float3 acc;
		float accw;
		float noise = 1.0 + IGN(vpos);
		float2 uvm = 0.5 * rcp(tex2Dsize(tex));
		float2 xy = vpos.xy * uvm;
		float cenD = GetDepth(xy);
		
		float2 avgSign;
		for(int i = -ITER; i <= ITER; i++) for(int ii = -ITER; ii <= ITER; ii++)
		{
			float2 off = sign(float2(i,ii)) * float2(i,ii) * float2(i,ii);
			float2 soff = uvm * noise*off;
			float3 sam = tex2DfetchLin(tex, 0.5 * vpos + noise*off).xyz;
			float samD = GetDepth(xy + soff);
			float w = exp(-10.0 * sam.z * length(sam.xy) );
			w *= exp(-level * 5.0 * abs(cenD - samD) / (cenD + 0.01));
			acc += w * float3((sam.xy), sam.z);
			accw += w;
			avgSign += w * sign(sam.xy);
		}
		return float4(2.0 * acc.xy / accw, 1.0 * acc.z / accw, 1.0);
	}
	float2 CurrLayer(sampler2D tex, int2 vpos, float level, int ITER)
	{
		float2 cen = tex2DfetchLin(tex, vpos).xy;
		float2 minm; float2 maxm; float2 t;
		
		float dir = 1.5707 * IGN(vpos + IGNSCROLL * level);
		float2 o;
		
		float2 tcord; float2 txy;
		float w;
		
		for(int i; i < ITER; i++)
		{
			minm = 9999.9; maxm = -9999.9;
			dir += 0.25 * 1.5707;
			o = (1.0 + i) * float2(sin(dir), cos(dir));
			
			txy = vpos + int2(o.y,o.x);
			t = tex2DfetchLin(tex, txy ).xy;
			cen += 0.25 * t / i;
			
			minm = min(minm, t); maxm = max(maxm, t);
			txy = vpos + int2(o.x,o.y);
			t = tex2DfetchLin(tex, txy ).xy;
			cen += 0.25 * t / i;
			
			minm = min(minm, t); maxm = max(maxm, t);
			cen /= 1.0 + 1.0 * rcp(i);
			cen = clamp(cen, minm, maxm);
			
		}
		
		return cen;
	}
	
	//=======================================================================================
	//Gaussian Pyramid
	//=======================================================================================
	
	float4 DUSample(sampler input, float2 xy, float div)//0.375 + 0.25
	{
	    float2 hp = div * rcp(RES);
		float4 acc;
	
		acc += 0.03125 * tex2D(input, xy + float2(-hp.x, hp.y));
		acc += 0.0625 * tex2D(input, xy + float2(0, hp.y));
		acc += 0.03125 * tex2D(input, xy + float2(hp.x, hp.y));
		
		acc += 0.0625 * tex2D(input, xy + float2(-hp.x, 0));
		acc += 0.125 * tex2D(input, xy + float2(0, 0));
		acc += 0.0625 * tex2D(input, xy + float2(hp.x, 0));
		
		acc += 0.03125 * tex2D(input, xy + float2(-hp.x, -hp.y));
		acc += 0.0625 * tex2D(input, xy + float2(0, -hp.y));
		acc += 0.03125 * tex2D(input, xy + float2(hp.x, -hp.y));
	  
		acc += 0.125 * tex2D(input, xy + 0.5 * float2(hp.x, hp.y));
		acc += 0.125 * tex2D(input, xy + 0.5 * float2(hp.x, -hp.y));
		acc += 0.125 * tex2D(input, xy + 0.5 * float2(-hp.x, hp.y));
		acc += 0.125 * tex2D(input, xy + 0.5 * float2(-hp.x, -hp.y));
		
	    return acc;
	}
	
	
	float Gauss0PS(PS_INPUTS) : SV_Target {
		float lum = pow(GetLuminance(pow(GetBackBuffer(xy), 2.2)), rcp(2.2));
		return pow(lum, 2.2); 
	}
	float Gauss1PS(PS_INPUTS) : SV_Target { return DUSample(sCG0, xy, 2.0).x; }
	float Gauss2PS(PS_INPUTS) : SV_Target { return DUSample(sCG1, xy, 4.0).x; }
	float Gauss3PS(PS_INPUTS) : SV_Target { return DUSample(sCG2, xy, 8.0).x; }
	float Gauss4PS(PS_INPUTS) : SV_Target { return DUSample(sCG3, xy, 16.0).x; }
	
	float Copy0PS(PS_INPUTS) : SV_Target { return tex2D(sCG0, xy).x; }
	float Copy1PS(PS_INPUTS) : SV_Target { return tex2D(sCG1, xy).x; }
	float Copy2PS(PS_INPUTS) : SV_Target { return tex2D(sCG2, xy).x; }
	float Copy3PS(PS_INPUTS) : SV_Target { return tex2D(sCG3, xy).x; }
	float Copy4PS(PS_INPUTS) : SV_Target { return tex2D(sCG4, xy).x; }
	
	float DGauss0PS(PS_INPUTS) : SV_Target { return GetDepth(xy); }
	float DGauss1PS(PS_INPUTS) : SV_Target { return DUSample(sDG0, xy, 2.0).x; }
	float DGauss2PS(PS_INPUTS) : SV_Target { return DUSample(sDG1, xy, 4.0).x; }
	
	//=======================================================================================
	//Motion Passes
	//=======================================================================================
	
	float4 Level4PS(PS_INPUTS) : SV_Target
	{
		return CalcMV(sCG4, sPG4, vpos.xy, 0, 3, 1);
	}
	
	float4 Level3PS(PS_INPUTS) : SV_Target
	{
		return CalcMV(sCG3, sPG3, vpos.xy, PrevLayer(sLevel4, vpos.xy, 1, 3), 2, 0);
	}
	
	float4 Level2PS(PS_INPUTS) : SV_Target
	{
		return CalcMV(sCG2, sPG2, vpos.xy, PrevLayer(sLevel3, vpos.xy, 1, 4), 1, 0);
	}
	
	float4 Level1PS(PS_INPUTS) : SV_Target
	{
		return CalcMV(sCG1, sPG1, vpos.xy, PrevLayer(sLevel2, vpos.xy, 1, 4), 1, 0);
	}
	
	float4 Level0PS(PS_INPUTS) : SV_Target
	{
		//if(FLOW_QUALITY == 0) discard;
		return CalcMV(sCG0, sPG0, vpos.xy, PrevLayer(sLevel1, vpos.xy, 1, 2), 1, 0);
	}
	
	//=======================================================================================
	//Final Filtering
	//=======================================================================================
	
	float2 FilterMV(sampler2D tex, sampler2D depTex, float2 vpos, float2 xy, int rad, float upscale, float offm)
	{
		float4 acc;
		float cenD = tex2Dfetch(depTex, vpos).x;
		//float2 cenMV = tex2Dfetch(tex, vpos / upscale).xy;
		float2 meanSign;
		
		for(int i = -rad; i <= rad; i++) for(int ii = -rad; ii <= rad; ii++)
		{
			int2 off = offm * int2(i,ii);
			float3 samp = tex2Dfetch(tex, (vpos + off) / upscale).xyz;
			float sampL = length(samp.xy);
			
			
			float samD = tex2Dfetch(depTex, vpos + off).x;
			
			
			float w = exp(-30.0 * abs(samD - cenD) / (exp2(-32) + cenD)) + 0.0001;
			//w *= exp(-0.01 * sampL * samp.z);
			//w *= any(sign(samp) == sign(cenMV));
			
			acc += w * float4(samp.xy, sampL, 1.0);
			meanSign += w * sign(samp.xy);
		}
		return acc.xy / acc.w;
	}
	
	float2 Filter0PS(PS_INPUTS) : SV_Target
	{
		//if(FLOW_QUALITY == 0) discard;
		return FilterMV(sLevel0, sDG2, vpos.xy, xy, 1, 1.0, 2.0);
		//return CurrLayer(sLevel0, vpos.xy, 4, 2);
	}
	
	float2 Filter1PS(PS_INPUTS) : SV_Target
	{
		//if(FLOW_QUALITY == 0) discard;
		return FilterMV(sLevel0t, sDG1, vpos.xy, xy, 1, 2.0, 2.0);
	}
	
	
	//=======================================================================================
	//Blending
	//=======================================================================================
	
	float2 SavePS(PS_INPUTS) : SV_Target
	{
	 float2 MV = FilterMV(sLevel00, sDG0, vpos.xy, xy, 1, 2.0, 2.0);
	 return any(abs(MV) > 0.1) ? MV / RES : 0.0;
	}
	
	float3 BlendPS(PS_INPUTS) : SV_Target
	{
		float2 MV = tex2D(sMV, xy).xy;
		return DEBUG ? MVtoRGB(200.0 * MV) : GetBackBuffer(xy);
	}
	
	technique QuarkMotion <
		ui_label = "Quark: Motion";
		    ui_tooltip =        
		        "								  	 Quark Motion - Created by Zenteon           \n"
		        "\n================================================================================================="
		        "\n"
		        "\nGenerates motion vectors for other shaders"
		        "\n"
		        "\n=================================================================================================";
		>	
	{
		pass {	PASS1(Gauss0PS, tCG0); }
		pass {	PASS1(Gauss1PS, tCG1); }
		pass {	PASS1(Gauss2PS, tCG2); }
		pass {	PASS1(Gauss3PS, tCG3); }
		pass {	PASS1(Gauss4PS, tCG4); }
		
		pass {	PASS1(DGauss0PS, tDG0); }
		pass {	PASS1(DGauss1PS, tDG1); }
		pass {	PASS1(DGauss2PS, tDG2); }
		//optical flow
		pass {	PASS1(Level4PS, tLevel4); }
		pass {	PASS1(Level3PS, tLevel3); }
		pass {	PASS1(Level2PS, tLevel2); }
		pass {	PASS1(Level1PS, tLevel1); }
		pass {	PASS1(Level0PS, tLevel0); }	
		pass {	PASS1(Filter0PS, tLevel0t); }	
		pass {	PASS1(Filter1PS, tLevel00); }	
		
		pass {	PASS1(Copy0PS, tPG0); }	
		pass {	PASS1(Copy1PS, tPG1); }
		pass {	PASS1(Copy2PS, tPG2); }
		pass {	PASS1(Copy3PS, tPG3); }
		pass {	PASS1(Copy4PS, tPG4); }
	
		pass {	PASS1(SavePS, texMotionVectors); }
		pass {	PASS0(BlendPS); }
	}
}
