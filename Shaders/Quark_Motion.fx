//========================================================================
/*
	Copyright © Daniel Oren-Ibarra - 2025
	All Rights Reserved.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND
	EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
	MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
	IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
	CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
	TORT OR OTHERWISE,ARISING FROM, OUT OF OR IN CONNECTION WITH THE
	SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
	
	
	======================================================================	
	Quark: Motion - Authored by Daniel Oren-Ibarra "Zenteon"
	
	Discord: https://discord.gg/PpbcqJJs6h
	Patreon: https://patreon.com/Zenteon


*/
//========================================================================
		
//Not sure what else to call this, half res vectors, half pixel precision
#ifndef SUBPIXEL_FLOW
	//============================================================================================
	#define SUBPIXEL_FLOW 0
	//============================================================================================
#endif

#include "ReShade.fxh"
#include "QuarkCommon.fxh"

uniform bool DEBUG <
	ui_label = "Debug Flow";
> = 0;


/*
	16 taps
 6
 5
 4
 3   o o o o 
 2   o o o o 
 1   o o o o 
 0   o o o o 
-1
-2

-2-1 0 1 2 3 4 5 6 

Big thanks to Marty for the idea
Lower noise, low cost increase, plays better with temporal stablization
	20 taps
 6
 5       o o
 4   o         o
 3     o     o
 2 o     o o     o 
 1 o     o o     o
 0     o     o 
-1   o         o
-2       o o

  -2-1 0 1 2 3 4 5 6 

*/

static const int2 off16[16] = {
	int2(0,0), int2(1,0), int2(2,0), int2(3,0),
	int2(0,1), int2(1,1), int2(2,1), int2(3,1),
	int2(0,2), int2(1,2), int2(2,2), int2(3,2),
	int2(0,3), int2(1,3), int2(2,3), int2(3,3)
	};

static const int2 off20[20] = {
		int2(1,5), int2(2,5),
		int2(-1,4), int2(4,4),
		int2(0,3), int2(3,3),
	int2(-2,2), int2(1,2), int2(2,2), int2(5,2),
	int2(-2,1), int2(1,1), int2(2,1), int2(5,1),
		int2(0,0), int2(3,0),
		int2(-1,-1), int2(4,-1),
		int2(1,-2), int2(2,-2),
		
	};
	#define BLOCK_POS_CT 20
	#define UBLOCK off20
	#define TEMPORAL 1
	
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
	#define LFORM RG16F
	#define LFILT POINT
	#define DIV_LEV (2 - SUBPIXEL_FLOW)
	//#define BLOCK_SIZE 4
	
	#define BLOCKS_SIZE 2
	
	//optical flow
	texture2D tLevel0 { DIVRES((2 * DIV_LEV)); Format = RGBA16F; MipLevels = 6; };
	sampler2D sLevel0 { Texture = tLevel0; MagFilter = POINT; MinFilter = LINEAR; MipFilter = LINEAR; };
	/*
	texture2D tTemp0 { DIVRES((1 * DIV_LEV)); Format = RGBA16F; };
	sampler2D sTemp0 { Texture = tTemp0; FILTER(POINT); };
	texture2D tTemp1 { DIVRES((1 * DIV_LEV)); Format = RGBA16F; };
	sampler2D sTemp1 { Texture = tTemp1; FILTER(POINT); };
	*/
	texture2D tLevel1 { DIVRES((4 * DIV_LEV)); Format = LFORM; };
	sampler2D sLevel1 { Texture = tLevel1; FILTER(LFILT); WRAPMODE(FWRAP); };
	texture2D tLevel2 { DIVRES((8 * DIV_LEV)); Format = LFORM; };
	sampler2D sLevel2 { Texture = tLevel2; FILTER(LFILT); WRAPMODE(FWRAP); };
	texture2D tLevel3 { DIVRES((16 * DIV_LEV)); Format = LFORM; };
	sampler2D sLevel3 { Texture = tLevel3; FILTER(LFILT); WRAPMODE(FWRAP); };
	texture2D tLevel4 { DIVRES((32 * DIV_LEV)); Format = LFORM; };
	sampler2D sLevel4 { Texture = tLevel4; FILTER(LFILT); WRAPMODE(FWRAP); };
	texture2D tLevel5 { DIVRES((64 * DIV_LEV)); Format = LFORM; };
	sampler2D sLevel5 { Texture = tLevel5; FILTER(LFILT); WRAPMODE(FWRAP); };
	
	//current
	texture2D tCG0 { DIVRES((0.5 * DIV_LEV)); Format = R16; };
	sampler2D sCG0 { Texture = tCG0; WRAPMODE(FWRAP); };
	texture2D tCG1 { DIVRES((1 * DIV_LEV)); Format = R16; };
	sampler2D sCG1 { Texture = tCG1; WRAPMODE(FWRAP); };
	texture2D tCG2 { DIVRES((2 * DIV_LEV)); Format = R16; };
	sampler2D sCG2 { Texture = tCG2; WRAPMODE(FWRAP); };
	texture2D tCG3 { DIVRES((4 * DIV_LEV)); Format = R16; };
	sampler2D sCG3 { Texture = tCG3; WRAPMODE(FWRAP); };
	texture2D tCG4 { DIVRES((8 * DIV_LEV)); Format = R16; };
	sampler2D sCG4 { Texture = tCG4; WRAPMODE(FWRAP); };
	texture2D tCG5 { DIVRES((16 * DIV_LEV)); Format = R16; };
	sampler2D sCG5 { Texture = tCG5; WRAPMODE(FWRAP); };
	//previous
	texture2D tPG0 { DIVRES((0.5 * DIV_LEV)); Format = R16; };
	sampler2D sPG0 { Texture = tPG0; WRAPMODE(FWRAP); };
	texture2D tPG1 { DIVRES((1 * DIV_LEV)); Format = R16; };
	sampler2D sPG1 { Texture = tPG1; WRAPMODE(FWRAP); };
	texture2D tPG2 { DIVRES((2 * DIV_LEV)); Format = R16; };
	sampler2D sPG2 { Texture = tPG2; WRAPMODE(FWRAP); };
	texture2D tPG3 { DIVRES((4 * DIV_LEV)); Format = R16; };
	sampler2D sPG3 { Texture = tPG3; WRAPMODE(FWRAP); };
	texture2D tPG4 { DIVRES((8 * DIV_LEV)); Format = R16; };
	sampler2D sPG4 { Texture = tPG4; WRAPMODE(FWRAP); };
	texture2D tPG5 { DIVRES((16 * DIV_LEV)); Format = R16; };
	sampler2D sPG5 { Texture = tPG5; WRAPMODE(FWRAP); };
	
		//=======================================================================================
	//Functions
	//=======================================================================================
	
	float IGN(float2 xy)
	{
	    float3 conVr = float3(0.06711056, 0.00583715, 52.9829189);
	    return frac( conVr.z * frac(dot(xy % RES,conVr.xy)) );
	}
	
	
	//=======================================================================================
	//Optical Flow Functions
	//=======================================================================================
	
	float4 tex2DfetchLin(sampler2D tex, float2 vpos)
	{
		//return tex2Dfetch(tex, vpos);
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
	
	float GetBlock(sampler2D tex, float2 vpos, float2 offset, float div, inout float Block[BLOCK_POS_CT] )
	{
		vpos = (vpos) * div;
		float acc;
		for(int i; i < BLOCK_POS_CT; i++)
		{
			int2 np = UBLOCK[i];
			float tCol = tex2DfetchLin(tex, vpos + np + offset).r;
			Block[i] = tCol;
			acc += tCol;
		}
		return acc / (BLOCK_POS_CT);
	}
	
	void GetBlockS(sampler2D tex, float2 vpos, float2 offset, float div, inout float Block[9] )
	{
		vpos = vpos;
		for(int i; i < 9; i++)
		{
			int2 np = int2(floor(float(i) / 3), i % 3) - 1;
			np = abs(np * np) + 1;
			float tCol = tex2DfetchLin(tex, vpos + np + offset).r;
			Block[i] = tCol;
		}
	}
	
	
	float BlockErr(float Block0[BLOCK_POS_CT], float Block1[BLOCK_POS_CT])
	{
		float3 ssd;
		for(int i; i < BLOCK_POS_CT; i++)
		{
			float2 t = 2.0 * (Block0[i] - Block1[i]) / (Block0[i] + Block1[i] + 0.001);
			ssd += abs(t);
		}
		
		return dot(ssd, 0.5) * rcp(BLOCK_POS_CT);
	}
	
	float BlockErrS(float Block0[9], float Block1[9])
	{
		float ssd;
		for(int i; i < 9; i++)
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
	
	float4 CalcMV(sampler2D cur, sampler2D pre, int2 pos, float4 off, int RAD, bool reject)
	{
	
		float cBlock[BLOCK_POS_CT];
		GetBlock(cur, pos, 0.0, 4.0, cBlock);
		
		float sBlock[BLOCK_POS_CT];
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
		
		//off += MV;
		//MV = 0;
		
		//if(Err > 0.33 && reject) return float4(0.0.xx, 1000.0, 1.0);
		
		//Err *= Err;
		return float4(MV + off.xy, off.z + Err, 1.0);
	}
	
	float4 PrevLayer(sampler2D tex, sampler2D depTexC, sampler2D depTexL, int2 vpos, float level, int ITER, float mult)
	{
		float3 acc = 0.0;//tex2DfetchLin(tex, 0.5 * vpos).xyz;
		float accw = 0.0;
		float noise = 1.0 + IGN(vpos);
		float2 uvm = 0.5 * rcp(tex2Dsize(tex));
		float2 xy = vpos.xy * uvm;
		float cenD = tex2Dlod(depTexC, float4(xy, 0, 0) ).y;
		
		float2 avgSign;
		for(int i = -ITER; i <= ITER; i++) for(int ii = -ITER; ii <= ITER; ii++)
		{
			float2 off = 2 * abs(float2(i,ii)) * float2(i,ii);
			float2 sxy = uvm * (vpos + off);
			float3 sam = tex2DfetchLin(tex, 0.5 * vpos + noise*off).xyz;
			float samD = tex2Dlod(depTexL, float4(sxy,0,0) ).y;
			
			
			float w = exp(-(abs(i) + abs(ii)) * 1.0 * sam.z) + 0.001;//
			w *= exp(-exp2(level) * 10.0 * abs(cenD - samD) / (cenD + 0.001)) + exp2(-32);
			float2 r = saturate(sxy * sxy - sxy);//thx ceejay
			w *= r.x == -r.y;
			
			float step = 0.5 * (1.0 - ( (ITER*(i + ITER) + (ii + ITER) + 1) / (4*ITER*ITER) ));
			
			//acc = lerp(acc, sam, 0.1 );
			acc += w * float3((sam.xy), sam.z);
			accw += w;
			avgSign += w * sign(sam.xy);
		}
		
		acc = acc / accw;// * float3(sign(avgSign), 1.0);
		
		
		//return float4(2.0 * tex2DfetchLin(tex, 0.5 * vpos).xyz, 1.0);
		return float4(2.0 * acc.xy, 1.0 * acc.z, 1.0);
	}
			
		static const int2 ioff[5] = { int2(0,0), int2(1,0), int2(0,1), int2(-1,0), int2(0,-1) };
		float4 PrevLayerL(sampler2D tex, sampler2D cur, sampler2D pre, float2 vpos, float level, int ITER, float mult)
		{
			float cBlock[BLOCK_POS_CT];
			GetBlock(cur, vpos, 0.0, mult, cBlock);
			
			float sBlock[BLOCK_POS_CT];
			GetBlock(pre, vpos, 0.0, mult, sBlock);
			
			float Err = BlockErr(cBlock, sBlock);
			float4 MV = tex2Dfetch(tex, 0.5 * vpos);
			
			for(int i = 1; i <= 1; i++) for(int ii; ii < 5; ii++)
			{
				float4 samMV = 2.0 * tex2Dfetch(tex, 2 * i * ioff[ii] + 0.5 * vpos);
				GetBlock(pre, vpos, samMV.xy, 4.0, sBlock);
				
				float tErr = BlockErr(cBlock, sBlock);
				
				[flatten]
				if(tErr < Err)
				{
					MV = samMV;
					Err = tErr;
				}
				
			}
			
			return MV;//
			//return float4(2.0 * tex2DfetchLin(tex, 0.5 * vpos).xyz, 1.0);
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
	
	float2 DUSample(sampler input, float2 xy, float div)//0.375 + 0.25
	{
		float2 hp = div * rcp(RES);
		float4 acc; float4 t;
		float minD = 1.0;
		
		t = tex2D(input, xy + float2(-hp.x, hp.y));
		acc += 0.03125 * t; minD = min(minD, t.y);
		
		t = tex2D(input, xy + float2(0, hp.y));
		acc += 0.0625 * t; minD = min(minD, t.y);
		
		t = tex2D(input, xy + float2(hp.x, hp.y));
		acc += 0.03125 * t; minD = min(minD, t.y);
		
		t = tex2D(input, xy + float2(-hp.x, 0));
		acc += 0.0625 * t; minD = min(minD, t.y);
		
		t = tex2D(input, xy + float2(0, 0));
		acc += 0.125 * t; minD = min(minD, t.y);
		
		t = tex2D(input, xy + float2(hp.x, 0));
		acc += 0.0625 * t; minD = min(minD, t.y);
		
		t = tex2D(input, xy + float2(-hp.x, -hp.y));
		acc += 0.03125 * t; minD = min(minD, t.y);
		
		t = tex2D(input, xy + float2(0, -hp.y));
		acc += 0.0625 * t; minD = min(minD, t.y);
		
		t = tex2D(input, xy + float2(hp.x, -hp.y));
		acc += 0.03125 * t; minD = min(minD, t.y);
		
		t = tex2D(input, xy + 0.5 * float2(hp.x, hp.y));
		acc += 0.125 * t; minD = min(minD, t.y);
		
		t = tex2D(input, xy + 0.5 * float2(hp.x, -hp.y));
		acc += 0.125 * t; minD = min(minD, t.y);
		
		t = tex2D(input, xy + 0.5 * float2(-hp.x, hp.y));
		acc += 0.125 * t; minD = min(minD, t.y);
		
		t = tex2D(input, xy + 0.5 * float2(-hp.x, -hp.y));
		acc += 0.125 * t; minD = min(minD, t.y);
		
		
		
		return acc.xy;//float2(acc.x, minD);
	}
	
	
	float2 Gauss0PS(PS_INPUTS) : SV_Target {
		float lum = pow(GetLuminance(pow(GetBackBuffer(xy), 2.2)), rcp(2.2));
		float dep = GetDepth(xy);
		return float2(pow(lum, 2.2), dep).xy; 
	}
	float2 Gauss1PS(PS_INPUTS) : SV_Target { return DUSample(sCG0, xy, 2.0).xy; }
	float2 Gauss2PS(PS_INPUTS) : SV_Target { return DUSample(sCG1, xy, 4.0).xy; }
	float2 Gauss3PS(PS_INPUTS) : SV_Target { return DUSample(sCG2, xy, 8.0).xy; }
	float2 Gauss4PS(PS_INPUTS) : SV_Target { return DUSample(sCG3, xy, 16.0).xy; }
	float2 Gauss5PS(PS_INPUTS) : SV_Target { return DUSample(sCG4, xy, 32.0).xy; }
	
	float Copy0PS(PS_INPUTS) : SV_Target { return tex2D(sCG0, xy).x; }
	float Copy1PS(PS_INPUTS) : SV_Target { return tex2D(sCG1, xy).x; }
	float Copy2PS(PS_INPUTS) : SV_Target { return tex2D(sCG2, xy).x; }
	float Copy3PS(PS_INPUTS) : SV_Target { return tex2D(sCG3, xy).x; }
	float Copy4PS(PS_INPUTS) : SV_Target { return tex2D(sCG4, xy).x; }
	float Copy5PS(PS_INPUTS) : SV_Target { return tex2D(sCG5, xy).x; }
	

	//=======================================================================================
	//Motion Passes
	//=======================================================================================
	
	float4 Level5PS(PS_INPUTS) : SV_Target
	{
		return CalcMV(sCG5, sPG5, vpos.xy, TEMPORAL * tex2Dlod(sLevel0, float4(xy, 0, 6) ) / 32, 4, 1);
	}
	
	float4 Level4PS(PS_INPUTS) : SV_Target
	{
		return CalcMV(sCG4, sPG4, vpos.xy, PrevLayerL(sLevel5, sCG4, sPG4, vpos.xy, 2, 1, 4.0), 2, 1);
	}
	
	float4 Level3PS(PS_INPUTS) : SV_Target
	{
		return CalcMV(sCG3, sPG3, vpos.xy, PrevLayerL(sLevel4, sCG3, sPG3, vpos.xy, 2, 1, 4.0), 1, 1);
	}
	
	float4 Level2PS(PS_INPUTS) : SV_Target
	{
		return CalcMV(sCG2, sPG2, vpos.xy, PrevLayerL(sLevel3, sCG2, sPG2, vpos.xy, 2, 1, 4.0), 1, 1);
	}
	
	float4 Level1PS(PS_INPUTS) : SV_Target
	{
		return CalcMV(sCG1, sPG1, vpos.xy, PrevLayerL(sLevel2, sCG1, sPG1, vpos.xy, 1, 1, 4.0), 1, 1);
	}
	
	float4 Level0PS(PS_INPUTS) : SV_Target
	{
		//if(FLOW_QUALITY == 0) discard;
		return CalcMV(sCG0, sPG0, vpos.xy, PrevLayerL(sLevel1, sCG0, sPG0, vpos.xy, 0, 1, 4.0), 1, 1);
	}
	
	//=======================================================================================
	//Final Filtering
	//=======================================================================================
	/*
	float3 JumpFlood(sampler2D tex, float2 xy, float level)
	{
		float3 fpos = tex2Dlod(tex, float4(xy, 0, 0)).xyz;

		[branch]
		if(any(fpos <= FARPLANE)) return fpos;
		float3 cpos = NorEyePos(xy);
		
		float2 mult = exp2(level) / tex2Dsize(tex);
		for(int i = -2; i <= 2; i++) for(int ii = -2; ii <= 2; ii++)
		{
			float2 nxy = xy + mult * float2(i, ii);
			float3 tpos = tex2Dlod(tex, float4(nxy,0,0)).xyz;
			[flatten]
			if(dot(cpos-tpos, cpos-tpos) < dot(cpos-fpos, cpos-fpos))
			{
				fpos = tpos;
			}
		}
		return fpos;
	}
	
	float4 PrepFloodPS(PS_INPUTS) : SV_Target
	{
		float doc = tex2D(sLevel0, xy ).z;
		float l = dot(GetBackBuffer(xy), 1.0);
		return float4( (doc > 100.0 || l <= exp2(-8) ) ? 10.0 * FARPLANE : NorEyePos(xy), 1.0);
	}
	
	float4 Flood5PS(PS_INPUTS) : SV_Target { return float4(JumpFlood(sTemp0, xy, 5.0), 1.0); }
	float4 Flood4PS(PS_INPUTS) : SV_Target { return float4(JumpFlood(sTemp1, xy, 4.0), 1.0); }
	float4 Flood3PS(PS_INPUTS) : SV_Target { return float4(JumpFlood(sTemp0, xy, 3.0), 1.0); }
	float4 Flood2PS(PS_INPUTS) : SV_Target { return float4(JumpFlood(sTemp1, xy, 2.0), 1.0); }
	float4 Flood1PS(PS_INPUTS) : SV_Target { return float4(JumpFlood(sTemp0, xy, 1.0), 1.0); }
	float4 Flood0PS(PS_INPUTS) : SV_Target { return float4(JumpFlood(sTemp1, xy, 0.0), 1.0); }
	*/
	//=======================================================================================
	//Blending
	//=======================================================================================
	
	float2 SavePS(PS_INPUTS) : SV_Target
	{
		//float2 fuv = GetScreenPos(tex2D(sTemp0, xy).xyz).xy;
		float2 MV = tex2D(sLevel0, xy ).xy / (1.0 + SUBPIXEL_FLOW);
		
		return any(abs(MV.xy) > 0.125) ? MV.xy / RES : 0.0;
	}
	
	float3 BlendPS(PS_INPUTS) : SV_Target
	{
		float2 MV = tex2D(sMV, xy).xy;
		
		MV *= 0.05 * RES;
		MV = lerp(MV, MV / (abs(MV) + 1.0), saturate(MV));
		return DEBUG ? MVtoRGB(MV) : GetBackBuffer(xy);
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
		pass {	PASS1(Gauss5PS, tCG5); }
	
		//optical flow
		pass {	PASS1(Level5PS, tLevel5); }
		pass {	PASS1(Level4PS, tLevel4); }
		pass {	PASS1(Level3PS, tLevel3); }
		pass {	PASS1(Level2PS, tLevel2); }
		pass {	PASS1(Level1PS, tLevel1); }
		pass {	PASS1(Level0PS, tLevel0); }	
		
		/*
		pass {	PASS1(PrepFloodPS, tTemp0); }	
		pass {	PASS1(Flood5PS, tTemp1); }
		pass {	PASS1(Flood4PS, tTemp0); }
		pass {	PASS1(Flood3PS, tTemp1); }
		pass {	PASS1(Flood2PS, tTemp0); }
		pass {	PASS1(Flood1PS, tTemp1); }
		pass {	PASS1(Flood0PS, tTemp0); }	
		*/
	
		pass {	PASS1(Copy0PS, tPG0); }	
		pass {	PASS1(Copy1PS, tPG1); }
		pass {	PASS1(Copy2PS, tPG2); }
		pass {	PASS1(Copy3PS, tPG3); }
		pass {	PASS1(Copy4PS, tPG4); }
		pass {	PASS1(Copy5PS, tPG5); }
	
		pass {	PASS1(SavePS, texMotionVectors); }
		pass {	PASS0(BlendPS); }
	}
}
