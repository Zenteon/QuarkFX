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
#include "QuarkCommon.fxh"
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
> = 1.0;

uniform float RAY_LENGTH <
	ui_min = 0.5;
	ui_max = 1.0;
	ui_type = "drag";
	ui_label = "Ray Length";
> = 1.0;

uniform float FADEOUT <
	ui_type = "drag";
	ui_label = "Depth Fadeout";
	ui_min = 0.0;
	ui_max = 1.0;
> = 0.8;

uniform int DEBUG <
	ui_type = "combo";
	ui_items = "None\0GI\0";
> = 0;

uniform int FRAME_COUNT <
	source = "framecount";>;

	//============================================================================
	//Bullshit
	//============================================================================

texture texMotionVectors { DIVRES(1); Format = RG16F; };
sampler MVSam0 { Texture = texMotionVectors; };	
	
namespace TurboGI2 {

	texture NormalTex { DIVRES(3); Format = RGBA8; MipLevels = 5; };
	texture NorDivTex { DIVRES(6); Format = RGBA8; MipLevels = 5; };
	texture DepDivTex { DIVRES(6); Format = R16; MipLevels = 5; };
	texture LumDivTex { DIVRES(6); Format = RGBA16F; MipLevels = 5; };
	
	sampler Normal { Texture = NormalTex; WRAPMODE(BORDER); };
	sampler NorDiv { Texture = NorDivTex; WRAPMODE(BORDER); };
	sampler DepDiv { Texture = DepDivTex; WRAPMODE(CLAMP); };
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
		nor.a = 0.0;
		
		float3 input = GetBackBuffer(xy);
		float inLum = GetLuminance(input);
		input = lerp(input, inLum, 0.5 * inLum*inLum*inLum*inLum);
		float3 GI = 5.0 * pow(input, 2.2) * tex2D(GISam, xy).rgb;
		lum = float4(IReinJ(input, HDR, 0, 0) + GI, 1.0);
		if(dep == 1.0) lum = float4(0.0.xxx, 1.0);
	}
	
	//============================================================================
	//GI
	//============================================================================
	#define FRAME_MOD (3.0 * (FRAME_COUNT % 32 + 1))
	
	float remapSin(float x)
	{
		//approximate sin(acos(x)) very poorly
		return saturate(1.0-x*x) / (0.5 * (1.0-x*x) + 0.5);
	}
	
	float GTAOContr(float3 viewV, float3 surfN, float3 projN, float2 minmax)
	{
		//float gm = saturate(acos(dot(-viewV, surfN)));
		float gm = saturate(acos(dot(viewV, projN)));
		return 0.25 * (-cos(2.0 * minmax.y - gm) + cos(gm) + 2.0*minmax.y*sin(gm) )
	    + 0.25 * (-cos(2.0*minmax.x) + cos(gm) + 2.0*minmax.x*sin(gm));
	}
	
	float4 CalcGI(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		xy = 3.0 * floor(xy * RES * 0.33334) / RES;
		float3 surfN = 2f * tex2D(Normal, xy).xyz - 1f;
		const float lr = length(RES);
		
		float3 posV  = NorEyePos(xy);
		float3 vieV  = -normalize(posV);
		if(posV.z == FARPLANE) discard;	
	
		float dir = 3.1415 * IGN(vpos.xy);
		float3 acc;
		float aoAcc;
		
		float2 minA;
		float attm = 1.0 + 0.05 * posV.z;//1.0;// + sqrt(0.1 * posV.z);
		for(int ii; ii < 3; ii++)
		{
			dir += 6.28 / 3.0;
			float2 off = float2(cos(dir), sin(dir));
			
			float dirW = clamp(1.0 / (1.0 + dot(normalize(surfN.xy + off), off)), 0.1, 3.0); //Debias weight			
			float rnd = IGN((FRAME_MOD + vpos.xy) % RES) + 0.5;
			//off = normalize(surfN.xy + off);
			float3 slcN = normalize(cross(float3(off, 0.0f), vieV));
			//float3 T = cross(vieV, slcN);
			//float3 RT = -normalize(cross(cross(surfN, vieV), surfN));//normalize(cross(surfN, float3(-off.y, off.x, 0.0)));
	    	float3 prjN = surfN - slcN * dot(surfN, slcN);
	    	float3 prjNN = normalize(prjN);
	   	 //float N = -sign(dot(prjN, T)) * acos( dot(normalize(prjN), vieV) );
	   	 
			off /= RES;
			float2 maxDot = -1.0;//T <= 0 ? -1.0 : -dot(prjN, vieV);//-sign(dot(prjN, T)) * dot(normalize(prjN), vieV);
			float2 maxAtt;
			float3 maxPos;
			float3 maxPos2;
			//uint bfd;
			
			for(int i = 1; i <= 9; i++) 
			{
				float lod = floor(4.5 / 9.0 * i);
				float2 sampXY = xy + rnd * RAY_LENGTH * 20.0 * pow(1.35, i) * off;
				if(sampXY.x > 1.0 || sampXY.x < 0.0) break;
				if(sampXY.y > 1.0 || sampXY.y < 0.0) break;
				
				float  sampD = tex2Dlod(DepDiv, float4(sampXY, 0, lod)).x + 0.0002;
				float3 sampN = 2f * tex2Dlod(NorDiv, float4(sampXY, 0, lod)).xyz - 1f;
				float3 sampL = tex2Dlod(LumDiv, float4(sampXY, 0, lod)).rgb;
				
				float3 posR  = GetEyePos(sampXY, sampD);
				float3 sV = normalize(posR - posV);
				//I got supremely lazy here
				float cDot = saturate(dot(prjNN, sV));
				float vDot = dot(vieV, sV);
				
				float att = rcp(1.0 + 0.05 * dot(posR.z - posV.z, posR.z - posV.z) / attm);
				cDot *= att;
				//att *= !any(abs(sampXY - 0.5) > 0.5);
				float sh = 1.0 - att;
				[flatten]
				if(cDot > maxDot.x) {
					maxDot.x = lerp(maxDot.x, cDot, 0.7);
				}
				
				[flatten]
				if(vDot > maxDot.y) {
					maxDot.y = lerp(maxDot.y, vDot, 0.7);
					sh = 1.0;
				}
				
				float  trns  = distance(xy, sampXY) * max(CalcTransfer(posV, prjNN, posR, sampN, 5.0, 1.0, 0.0), 0.0);
				trns *= pow(1.35, i) / pow(1.35, i - 1.0);
				trns *= dot(sV, surfN) > 0.0;
				acc += dirW * sh * sampL * trns;
			}
			//maxDot = max(acos(maxDot), -3.14159);
			//maxDot = cos(acos(maxDot) - N);
			//maxDot = max(maxDot.x, maxDot.y);//maxDot.x < maxDot.y ? maxDot.yx : maxDot;
			aoAcc += maxDot.x;//clamp(1.0-maxDot, 0.0, 1);
			
			//maxDot = acos(maxDot * float2(-1,1));
			//float cenA = cos(0.5 * (maxDot.x + maxDot.y));
			
		}
		return float4(ReinJ(lr * acc / (9.0 * 3.0), HDR, 0, 0), 1.0 - aoAcc / 3.0);
	
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
		xy = 3.0 * floor(xy * RES * 0.33334) / RES;
		
		float4 acc = tex2D(CurSam, xy);
		float pAO = acc.a;
		float accW = 1.0;
		
		for(int i = -2; i <= 2; i++) for(int ii = -2; ii <= 2; ii++)
		{
			float2 offset = 6.0 * float2(i, ii) / RES;
			
			float4 sampC = tex2Dlod(CurSam, float4(xy + offset, 0, 0));
			float  sampD = tex2D(DepDiv, xy + offset).x;
			//float3 sampN = 2f * tex2D(NorDiv, xy + offset).xyz - 1f;
			
			float  wN = 1.0;//pow(saturate(dot(surfN, sampN)), 1.0);
			float  wD = exp(-abs(surfD - sampD) * (100.0 / surfD) * adpThrsh);
			acc += wD * wN * sampC;
			accW += wD * wN;
		}
		return acc / accW;
		//return float4(acc.rgb / accW, acc.a / accW);
		//return float4(acc.rgb / accW, pAO);
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
			float2 offset = 3.0 * float2(i, ii) / RES;
			
			float4 sampC = tex2Dlod(DenSam0, float4(xy + offset, 0, 0));
			float  sampD = tex2D(DepDiv, xy + offset).x;
			//float3 sampN = 2f * tex2D(NorDiv, xy + offset).xyz - 1f;
			float  wN = 1.0;//pow(saturate(dot(surfN, sampN)), 1.0);
			float  wD = exp(-abs(surfD - sampD) * (100.0 / surfD) * adpThrsh);
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
		
		return lerp(cur, pre, DEG * 0.85);
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
		float2 se = float2(0.0, 0.001 + 0.999 * FADEOUT);
		se.y = max(se.y, se.x + 0.001);
		
		d = saturate(1.0 / (se.y) * d - se.x);
	
		float f = 1.0 - 1.0 / exp(pow(d * den, 2.0));
		
		return saturate(f);
	}
	
	float3 Albedont(float2 xy)
	{
		float3 c = GetBackBuffer(xy + 0.5 / RES);
		float cl = dot(c, 0.3);//GetLuminance(c);
		float g = abs(ddx_fine(cl)) + abs(ddy_fine(cl));
		c = 0.95 * c / (0.1 + cl);
		c*=c;
		
		
		//cl = cl / (cl + 1.0);
		//cl = sqrt(cl);
		return lerp(c*cl, cl, 0.0);
		
		//c = SRGBtoOKLAB(c);
		//c.x = sqrt(c.x);
		//c = OKLABtoSRGB(c);
		//return pow(c, 2.2);
	}
	
	float3 SRGBtoOKLAB(float3 c) 
				{
				    float l = 0.4122214708f * c.r + 0.5363325363f * c.g + 0.0514459929f * c.b;
					float m = 0.2119034982f * c.r + 0.6806995451f * c.g + 0.1073969566f * c.b;
					float s = 0.0883024619f * c.r + 0.2817188376f * c.g + 0.6299787005f * c.b;
				
				    float l_ = pow(l, 0.3334);
				    float m_ = pow(m, 0.3334);
				    float s_ = pow(s, 0.3334);
				
				   return float3(
				        0.2104542553f*l_ + 0.7936177850f*m_ - 0.0040720468f*s_,
				        1.9779984951f*l_ - 2.4285922050f*m_ + 0.4505937099f*s_,
				        0.0259040371f*l_ + 0.7827717662f*m_ - 0.8086757660f*s_);
				}
				
				float3 OKLABtoSRGB(float3 c) 
				{
				    float l_ = c.x + 0.3963377774f * c.y + 0.2158037573f * c.z;
				    float m_ = c.x - 0.1055613458f * c.y - 0.0638541728f * c.z;
				    float s_ = c.x - 0.0894841775f * c.y - 1.2914855480f * c.z;
				
				    float l = l_*l_*l_;
				    float m = m_*m_*m_;
				    float s = s_*s_*s_;
				
				    return float3(
						 4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s,
						-1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s,
						-0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s);
				}
				
				/*
				float3 Albedont(float2 xy)
				{
					float3 c = GetBackBuffer(xy);
					c *= c;
					c = SRGBtoOKLAB(c);
					//c.x = sqrt(c.x);
					//c.x *= 2.0;
					c.x /= lerp(c.x, 1.0, 0.9);
					c = OKLABtoSRGB(c);
					return c;
				}
				*/
	float3 Blend(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		
		float3 input = tex2D(ReShade::BackBuffer, xy).rgb;
		float3 prein = input;
		
		//depth thing
		float depth = GetDepth(xy);
		if(depth == 1.0) return lerp(input, 0.5, DEBUG);
		float lerpVal = CalcFog(depth, 1.0);
		
		//AO
		float4 GI, tGI; // = tex2D(DenSam1, xy);// * pow(input, 2.2);
		float w, tW;
		float2 tpos;
		
		tpos = floor(0.5 * vpos.xy) + int2(0, 0);
		tGI = tex2Dfetch(DenSam1, tpos);
		tW = rcp(0.0001 + abs(GetDepth(2.0 * tpos / RES) - depth));
		GI += tGI * tW;
		w += tW;
		
		tpos =  floor(0.5 * vpos.xy) + int2(0, 1);
		tGI = tex2Dfetch(DenSam1, tpos);
		tW = rcp(0.0001 + abs(GetDepth(2.0 * tpos / RES) - depth));
		GI += tGI * tW;
		w += tW;
		
		tpos =  floor(0.5 * vpos.xy) + int2(1, 0);
		tGI = tex2Dfetch(DenSam1, tpos);
		tW = rcp(0.0001 + abs(GetDepth(2.0 * tpos / RES) - depth));
		GI += tGI * tW;
		w += tW;
		
		tpos =  floor(0.5 * vpos.xy) + int2(1, 1);
		tGI = tex2Dfetch(DenSam1, tpos);
		tW = rcp(0.0001 + abs(GetDepth(2.0 * tpos / RES) - depth));
		GI += tGI * tW;
		w += tW;
		
		GI /= w;
		
		//GI = tex2D(DenSam1, xy);
		
		float AO = GI.a;
		AO = lerp(1.0, AO, 0.95 * AO_INTENSITY);
		
		//GI.rgb *= AO;
		
		//Debug out
		//GI = tex2Dfetch(GISam, vpos.xy);
		//AO = GI.a;
		if(DEBUG) return lerp(ReinJ(AO*AO * 0.05 + IReinJ(GI.rgb, HDR, 0, 0) * INTENSITY, HDR, 0, 0), 0.5, lerpVal);
		
		//Fake albedo
		//float inGray = prein.r + prein.g + prein.b;
		float3 albedo = Albedont(xy);//pow(2.0 * prein / (1.0 + inGray), 2.2);
		
		//GI blending
		GI.rgb = IReinJ(GI.rgb, HDR, 0, 0);
		GI.rgb *= INTENSITY * albedo;
		input = IReinJ(input, HDR, 0, 0);
		
		
		
		return lerp(ReinJ(AO * input + AO * GI.rgb, HDR, 0, 0), prein, lerpVal);
	
	}
	
	technique TurboGI <
		ui_label = "Quark: Turbo GI";
		    ui_tooltip =        
		        "								   Quark TurboGI - Made by Zenteon           \n"
		        "\n================================================================================================="
		        "\n"
		        "\nTurbo GI is a free lightweight global illumination and AO shader with a rendering budget of"
		        "\n1ms on a 3050 mobile"
		        "\n"
		        "\n=================================================================================================";
		>	
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
