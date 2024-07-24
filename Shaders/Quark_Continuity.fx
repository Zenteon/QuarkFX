#include "ReShade.fxh"
#include "ContinuityCommon.fxh"

#if(__RENDERER__ != 0x9000)

	uniform int FRAME_COUNT <
			source = "framecount";>;
	
	uniform bool DO_SMOOTH <
		ui_label = "Smoothed Normals";
	> = 0;
	
	uniform bool DO_TEX <
		ui_label = "Textured Normals";
	> = 0;
	
	uniform float TEX_LEVEL <
		ui_type = "slider";
		ui_label = "Textured Normals Intensity";
		ui_min = 0.0;
		ui_max = 1.0;
	> = 0.7;
	
	uniform float TEX_RAD <
		ui_type = "slider";
		ui_label = "Textured Normals Width";
		ui_min = 1.0;
		ui_max = 3.0;
	> = 1.0;
	//===================================================================================
	//Textures/Samplers
	//===================================================================================
	namespace Continuity {
	
		texture DownTex0 { HALFTEX; Format = RGBA8;	MipLevels = 1; }; 
		texture DownTex1 { QUARTEX; Format = RGBA8;	MipLevels = 1; }; 
		texture NorTex0 { FULLTEX; Format = RGBA16; MipLevels = 6; };
		texture NorTex1 { FULLTEX; Format = RGBA16; MipLevels = 6; };
		texture LumTex0 { FULLTEX; Format = R8;	MipLevels = 1; };
		
		texture HoleMask { FULLTEX; Format = R8; };
		
		
		//texture LumTex1 { FULLTEX; Format = R8;	MipLevels = 1; };
		//texture DownTex { HALFTEX; Format = R8;	MipLevels = 1; }; 
		
		
		sampler DownSam0 { Texture = DownTex0; };
		sampler DownSam1 { Texture = DownTex1; };
		sampler LumSam0 { Texture = LumTex0; };
		//sampler LumSam1 { Texture = LumTex1; };
		//sampler DownSam { Texture = DownTex; };
		sampler NorSam0 { Texture = NorTex0; };
		sampler NorSam1 { Texture = NorTex1; };
		
		sampler NorHole { Texture = HoleMask; FILTER(POINT); };
		
		//===================================================================================
		//LumKawase Blur Passes
		//===================================================================================
		
		float LumDownSample(sampler TEX, float2 xy, float rdiv)
		{
			float2 res	   = float2(BUFFER_WIDTH, BUFFER_HEIGHT) / rdiv;
		    float2 hp		= 0.5 / res;
		    float  offset	= 1.0;
		
		    float acc = tex2D(TEX, xy).r * 4.0;
		    acc += tex2D(TEX, xy - hp * offset).r;
		    acc += tex2D(TEX, xy + hp * offset).r;
		    acc += tex2D(TEX, xy + float2(hp.x, -hp.y) * offset).r;
		    acc += tex2D(TEX, xy - float2(hp.x, -hp.y) * offset).r;
		
		    return acc / 8.0;
		}
	
		float LumUpSample(sampler TEX, float2 xy, float rdiv)
		{
			float2 res	   = float2(BUFFER_WIDTH, BUFFER_HEIGHT) / rdiv;
		    float2 hp		= 0.5 / res;
		    float  offset	= 1.0;
			float  acc	   = tex2D(TEX, xy + float2(-hp.x * 2.0, 0.0) * offset).r;
		    
		    acc += tex2D(TEX, xy + float2(-hp.x, hp.y) * offset).r * 2.0;
		    acc += tex2D(TEX, xy + float2(0.0, hp.y * 2.0) * offset).r;
		    acc += tex2D(TEX, xy + float2(hp.x, hp.y) * offset).r * 2.0;
		    acc += tex2D(TEX, xy + float2(hp.x * 2.0, 0.0) * offset).r;
		    acc += tex2D(TEX, xy + float2(hp.x, -hp.y) * offset).r * 2.0;
		    acc += tex2D(TEX, xy + float2(0.0, -hp.y * 2.0) * offset).r;
		    acc += tex2D(TEX, xy + float2(-hp.x, -hp.y) * offset).r * 2.0;
		
		    return acc / 12.0;
		}
		
		//===================================================================================
		//Kawase Blur Passes
		//===================================================================================
		
		float3 DownSample(sampler TEX, float2 xy, float rdiv)
		{
			float2 res	   = float2(BUFFER_WIDTH, BUFFER_HEIGHT) / rdiv;
		    float2 hp		= 0.5 / res;
		    float  offset	= 1.0;
		
		    float3 acc = tex2D(TEX, xy).rgb * 4.0;
		    acc += tex2D(TEX, xy - hp * offset).rgb;
		    acc += tex2D(TEX, xy + hp * offset).rgb;
		    acc += tex2D(TEX, xy + float2(hp.x, -hp.y) * offset).rgb;
		    acc += tex2D(TEX, xy - float2(hp.x, -hp.y) * offset).rgb;
		
		    return acc / 8.0;
		}
		
		float3 UpSample(sampler TEX, float2 xy, float rdiv)
		{
			float2 res	   = float2(BUFFER_WIDTH, BUFFER_HEIGHT) / rdiv;
		    float2 hp		= 0.5 / res;
		    float  offset	= 1.0;
			float3  acc	   = tex2D(TEX, xy + float2(-hp.x * 2.0, 0.0) * offset).rgb;
		    
		    acc += tex2D(TEX, xy + float2(-hp.x, hp.y) * offset).rgb * 2.0;
		    acc += tex2D(TEX, xy + float2(0.0, hp.y * 2.0) * offset).rgb;
		    acc += tex2D(TEX, xy + float2(hp.x, hp.y) * offset).rgb * 2.0;
		    acc += tex2D(TEX, xy + float2(hp.x * 2.0, 0.0) * offset).rgb;
		    acc += tex2D(TEX, xy + float2(hp.x, -hp.y) * offset).rgb * 2.0;
		    acc += tex2D(TEX, xy + float2(0.0, -hp.y * 2.0) * offset).rgb;
		    acc += tex2D(TEX, xy + float2(-hp.x, -hp.y) * offset).rgb * 2.0;
		
		    return acc / 12.0;
		}
		
		float2 GetSobel(sampler input, float2 xy, float div, float3 nor)
		{
			
			//float dd = GetDepDer(xy);
			float3 pos = NorEyePos(xy);
			//float2 norOff = 1.0 - abs(nor.xy);
			//float cd = GetDepth(xy);
			float2 hp = div / (RES);// + (dd * 1.0 * FARPLANE));
			//float3 viewV = normalize(pos);
			float nMul = 1.0;// / (abs(dot(nor, viewV)) + 0.05);
			
			
			float3 acc;//x, y, normalization value
			for(int i = -1; i <= 1; i++) for(int ii = -1; ii <= 1; ii++)
			{
				float2 offset = hp * float2(i, ii);
				
				float3 tpos = NorEyePos(xy + offset);
				float wd = exp( -10.0 * abs( dot(nor, tpos - pos)));
				float xmul = 1.0;//0.5 * (abs(i) == 1.0);
				float ymul = 1.0;//0.5 * (abs(ii) == 1.0);
				
				acc += tex2D(input, xy + offset).r * float3(i, ii, 1.0 / (wd + 0.001) );// * exp( -distance(vpos, ovpos) );
			
			}
			
			/*float2 acc  = 0.25 * float2(-1.0, -1.0) * tex2D(input, xy + float2(-hp.x, -hp.y)).r;
				   acc += float2(-1.0, 0.0) * tex2D(input, xy + float2(-hp.x, 0.0)).r;
				   acc += 0.25 * float2(-1.0, 1.0) * tex2D(input, xy + float2(-hp.x, hp.y)).r;
				   
				   acc += float2(0.0, -1.0) * tex2D(input, xy + float2(0.0, -hp.y)).r;
				   acc += float2(0.0, 0.0) * tex2D(input, xy + float2(0.0, 0.0)).r;
				   acc += float2(0.0, 1.0) * tex2D(input, xy + float2(0.0, hp.y)).r;
				   
				   acc += 0.25 * float2(1.0, -1.0) * tex2D(input, xy + float2(hp.x, -hp.y)).r;
				   acc += float2(1.0, 0.0) * tex2D(input, xy + float2(hp.x, 0.0)).r;
				   acc += 0.25 * float2(1.0, 1.0) * tex2D(input, xy + float2(hp.x, hp.y)).r;
			*/	   
			
			acc.z /= 9.0;
			
			return 8.0 * TEX_LEVEL * TEX_LEVEL * nMul * acc.xy / (acc.z + 0.1);// * (1.0 + 10.0 * dd);//10.0 * acc * (1.0 + 20.0 * dd);
		}
		
		//===================================================================================
		//Downscale Passes
		//===================================================================================
		float4 Down0(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
		{	return float4(DownSample(ReShade::BackBuffer, texcoord, 2.0), 1.0);	}
		
		float4 Down1(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
		{	return float4(DownSample(DownSam0, texcoord, 4.0), 1.0);	}
		
		float4 Up0(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
		{	return float4(UpSample(DownSam1, texcoord, 4.0), 1.0);	}
		
		float4 Up1(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target {	
			float3 blur = UpSample(DownSam0, texcoord, 2.0);
			float  blurL =  0.3777 + 0.2 * (blur.r + blur.g + blur.b);
			float3 input = tex2D(ReShade::BackBuffer, texcoord).rgb;
			
			return float4(pow(input / blurL, 2.2) , 1.0);//float4(pow(0.8 * input / (blur + 0.2), 1.75), 1.0);
		}
	
		
		//===================================================================================
		//Texture Passes
		//===================================================================================
		
		float LuminBuffer(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			if(!DO_TEX) return 0;
			float2 hp = 0.5 / RES;
			float3 input = GetBackBuffer(xy);//0.5 * abs(GetBackBuffer(xy) + UpSample(ReShade::BackBuffer, xy, 1.5));
			
			input = saturate(input);
			
			return pow( (0.2126 * input.r + 0.7152 * input.g + 0.0722 * input.b), 1.0);
		}
		
		
	
		void HeightNor(float4 vpos : SV_Position, float2 xy: TexCoord, out float2 cnor : SV_Target0, out float4 nor : SV_Target1)
		{
			//if(!DO_TEX) return NormalEncode(2f * tex2D(NorSam1, texcoord).xyz - 1f);
			/*float hm = 0.05;
			float dm = 1.0;
			float3 vc	  = float3(texcoord, hm * tex2D(LumSam0, texcoord).x);
			
		
			float2 xy	   = texcoord + float2(dm, 0) / RES;
			float3 vx0	  = vc - float3(xy, hm * tex2D(LumSam0, xy).x);
			
				   xy	   = texcoord + float2(0, dm) / RES;		
			float3 vy0 	 = vc - float3(xy, hm * tex2D(LumSam0, xy).x);
				   xy	   = texcoord - float2(dm, 0) / RES;
			float3 vx1	  = -vc + float3(xy, hm * tex2D(LumSam0, xy).x);
			
				   xy	   = texcoord - float2(0, dm) / RES;
			float3 vy1 	 = -vc + float3(xy, hm * tex2D(LumSam0, xy).x);
			
			float3 vx = abs(vx0.z) < abs(vx1.z) ? vx0 : vx1;
			float3 vy = abs(vy0.z) < abs(vy1.z) ? vy0 : vy1;
			
			float3 texN = normalize(cross(vy, vx));
			*/
			
			float3 surfN = 2f * tex2D(NorSam1, xy).xyz - 1f;
			float3 viewV = normalize(NorEyePos(xy));
			
			float2 sobel = GetSobel(LumSam0, xy, 1.0 * TEX_RAD, surfN);
			sobel += 0.5 * GetSobel(LumSam0, xy, 2.0 * TEX_RAD, surfN);
			//sobel += 0.25 * GetSobel(LumSam0, texcoord, 3.0 * TEX_RAD, surfN);
			//sobel += -GetSobel(LumSam0, texcoord, 8.0 * TEX_RAD);
			
			float3 texN = normalize(float3(sobel, 1.0));
			//dtexN = -normalize(-viewV + texN * dot(texN, -viewV) );
			//texN *= -1.0;
			surfN *= -1.0;
			
			//surfN = -normalize(lerp(surfN, surfN + texN * dot(surfN, texN), 1.0 * TEX_LEVEL));
			
			
			float3 n1 = surfN;
			float3 n2 = normalize(texN);
			
			float3x3 nBasis = float3x3(
			    float3(n1.z, n1.y, -n1.x), // +90 degree rotation around y axis
			    float3(n1.x, n1.z, -n1.y), // -90 degree rotation around x axis
			    float3(n1.x, n1.y,  n1.z));
			
			float3 r = normalize(n2.x*nBasis[0] + n2.y*nBasis[1] + n2.z*nBasis[2]);
			//r*0.5 + 0.5;
			
			//surfN = normalize( float3(surfN.xy * texN.z + texN.xy * surfN.z, surfN.z * texN.z) );//normalize(texN * dot(surfN, texN) / texN.z - surfN);
			//surfN = normalize(texN * dot(surfN, texN) / texN.z - surfN);
			//texN.xy *= -1.0;
			//texN.xy /= texN.z;
			//texN.z = saturate(texN.z);
			//surfN.xy /= surfN.z;
			texN = lerp(float3(0.0, 0.0, 1.0), texN, 0.4);
			surfN = normalize(float3(surfN.xy + texN.xy, surfN.z * texN.z));
			//surfN.z = saturate(surfN.z);
			//surfN = normalize(surfN);
			
			//float3 tempN = normalize(float3(surfN.xy / surfN.z + texN.xy / texN.z, 1.0));
			
			//texN.z *= -1.0;
			//texN.xy *= -1.0;//normalize(float3(-texN.xy, saturate(texN.z)) );
			cnor = NormalEncode(-surfN);//distance(surfN, texN).xx;//NormalEncode(texN);
			nor = float4(0.5 + 0.5 * texN, 1.0);
		}
		
		
		//===================================================================================
		//Normals
		//===================================================================================
	
		void GenNorBuffer(float4 vpos : SV_Position, float2 texcoord : TexCoord, out float4 normal : SV_Target0, out float depDeriv : SV_Target1) 
		{
			float3 vc	  = NorEyePos(texcoord);
			
			float3 vx0	  = vc - NorEyePos(texcoord + float2(1, 0) / RES);
			float3 vy0 	 = vc - NorEyePos(texcoord + float2(0, 1) / RES);
			
			float3 vx1	  = -vc + NorEyePos(texcoord - float2(1, 0) / RES);
			float3 vy1 	 = -vc + NorEyePos(texcoord - float2(0, 1) / RES);
			
			float3 vx01	  = vc - NorEyePos(texcoord + float2(2, 0) / RES);
			float3 vy01 	 = vc - NorEyePos(texcoord + float2(0, 2) / RES);
				
			float3 vx11	  = -vc + NorEyePos(texcoord - float2(2, 0) / RES);
			float3 vy11 	 = -vc + NorEyePos(texcoord - float2(0, 2) / RES);
			
			float dx0 = abs(vx0.z + (vx0.z - vx01.z));
			float dx1 = abs(vx1.z + (vx1.z - vx11.z));
			
			float dy0 = abs(vy0.z + (vy0.z - vy01.z));
			float dy1 = abs(vy1.z + (vy1.z - vy11.z));
			
			float3 vx = dx0 < dx1 ? vx0 : vx1;
			float3 vy = dy0 < dy1 ? vy0 : vy1;
			//float3 vx = abs(vx0.z) < abs(vx1.z) ? vx0 : vx1;
			//float3 vy = abs(vy0.z) < abs(vy1.z) ? vy0 : vy1;
			
			float3 output = 0.5 + 0.5 * normalize(cross(vy, vx));
			
			depDeriv = abs(vx.z + vy.z);
			normal = float4(output, 1.0);
		}
		
		//fill holes in normals
		void FillNorBuffer(float4 vpos : SV_Position, float2 xy : TexCoord, out float4 normal : SV_Target0, out float depDeriv : SV_Target1) 
		{
			depDeriv = tex2D(NorHole, xy).x;
			normal = 2f * tex2D(NorSam0, xy) - 1f;
			
			
			
			float2 fp = 1.0 / RES;
			if(round(depDeriv + 0.4) > 0)
			{
				normal = 0.0; depDeriv = 0.0;
				
				
				normal += 2f * tex2D(NorSam0, xy + float2(fp.x, 0.0)) - 1f;	 depDeriv += tex2D(NorHole, xy + float2(fp.x, 0.0)).x;
				normal += 2f * tex2D(NorSam0, xy + float2(-fp.x, 0.0)) - 1f;	depDeriv += tex2D(NorHole, xy + float2(-fp.x, 0.0)).x;
				normal += 2f * tex2D(NorSam0, xy + float2(0.0, fp.y)) - 1f;	 depDeriv += tex2D(NorHole, xy + float2(0.0, fp.y)).x;
				normal += 2f * tex2D(NorSam0, xy + float2(0.0, -fp.y)) - 1f;	depDeriv += tex2D(NorHole, xy + float2(0.0, -fp.y)).x;
				normal *= 0.25; depDeriv *= 0.25;
			}
			normal = 0.5 + 0.5 * normalize(normal);
		}
		
		
		#define RAD 4
		
		float3 NorSmooth(sampler tex, float2 xy, bool x)
		{
			
			float3 cenN	= 2f * tex2D(tex, xy).xyz - 1f;
			if(!DO_SMOOTH) return cenN;
			float  cenD	= ReShade::GetLinearizedDepth(xy);
			float3 surfVP  = GetEyePos(xy, cenD);
			
			float pdDep = tex2D(NorHole, xy).x;//(ddy(cenD) + ddx(cenD));//
			
			float3 acc 	= cenN;	//Accumulated Blending
			float  accW	= 1.0;	//Accumulated Weights
			
			float2 hp = 1.0 / RES; 
			
			float3 edgeM = 2f * tex2Dlod(tex, float4(xy, 0, 1)).xyz - 1f;
				   //edgeM += 2f * tex2D(tex, xy + float2(hp.x, -hp.y)).xyz - 1f;
				   //edgeM += 2f * tex2D(tex, xy + float2(-hp.x, hp.y)).xyz - 1f;
				   //edgeM += 2f * tex2D(tex, xy + float2(-hp.x, -hp.y)).xyz - 1f;
			
			edgeM = 1.0 - 2.0 * distance(edgeM, cenN);
			
			float4 minN;
			float4 maxN;
			
			for(int i = -RAD; i <= RAD; i++)
			{
				//if(i == 0) continue;
				float2 offset	= 2.0 * sign(i) * pow(abs(i) + 1, 1.2) * float2(x, !x) / RES;
				float3 curN	  = 2f * tex2Dlod(tex, float4(xy + offset, 0, 1)).xyz - 1f;
				float  curD	  = ReShade::GetLinearizedDepth(xy + offset);
				
				float3 tempVP = GetEyePos(xy + offset, curD);
				
				float wG = 1.0;// + abs(i - pow(abs(i), 1.2));//1.0;//exp(-pow((2.0 / RAD) * i, 2.0));
				float wN = saturate(dot(cenN, curN)) >= 0.4;
				float wD = exp( -8.0 * abs(dot(cenN, tempVP - surfVP)) );//exp(-2.5 * distance(cenD, curD) / (abs(pdDep * (cenD - curD)) + 0.001) );//exp(-distance(cenD, curD) * 10000.0);
				
				acc  += curN * wN * wD * wG;
				accW += wN * wD * wG;
				
			}
		
			return normalize(acc / accW);
		}
	
		//===================================================================================
		//Normal Passes
		//===================================================================================
		
		float4 SmoothNormals0(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
		{
			float3 Normals = NorSmooth(NorSam1, texcoord, 1).xyz;
			return float4(0.5 + 0.5 * Normals, 1f);
		}
		
		float4 SmoothNormals1(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
		{
			float3 Normals = NorSmooth(NorSam0, texcoord, 0).xyz;
			return float4(0.5 + 0.5 * Normals, 1f);
		}
		
		float2 SaveSamN(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
		{
			return tex2D(Continuity::NormalBuffer, texcoord).xy;
		}
		
		float SaveSamD(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
		{
			float2 hp = 1.0 / RES; //half res render target
			float d = 1.0;
			
			
			d = min(d, ReShade::GetLinearizedDepth(texcoord + float2(hp.x, hp.y) ) );
			d = min(d, ReShade::GetLinearizedDepth(texcoord + float2(hp.x, -hp.y) ) );
			d = min(d, ReShade::GetLinearizedDepth(texcoord + float2(-hp.x, hp.y) ) );
			d = min(d, ReShade::GetLinearizedDepth(texcoord + float2(-hp.x, -hp.y) ) );
			
			/*
			d = max(d, ReShade::GetLinearizedDepth(texcoord + float2(hp.x, hp.y) ) );
			d = max(d, ReShade::GetLinearizedDepth(texcoord + float2(hp.x, -hp.y) ) );
			d = max(d, ReShade::GetLinearizedDepth(texcoord + float2(-hp.x, hp.y) ) );
			d = max(d, ReShade::GetLinearizedDepth(texcoord + float2(-hp.x, -hp.y) ) );
			*/
			return d;
		}
		
		float3 CNNormal(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
		{
			float3 input = 0.5 + 0.5 * GetNormal(texcoord);
			return input;
		}
		
		//===================================================================================
		//Thickness Passes
		//===================================================================================
		float IGN(float2 xy)
		{
		    float3 conVr = float3(0.06711056, 0.00583715, 52.9829189);
		    return frac( conVr.z * frac(dot(xy,conVr.xy)) );
		}
		
		float TraceTHICC(float2 xy, float3 surfN, float surfD, float2 offset, float jitter)
		{
			float3 surfVP = GetEyePos(xy, surfD);
		
			float maxA;//horizon vector, vector dot
			float maxP;
			float dmult = 10.0 + 40.0 / length(surfVP);
			
			for(int i = 1; i <= 4; i++)
			{
				float2 npos = xy + dmult * offset * (i * jitter);
				if(abs(npos.x - 0.5) > 0.5 || abs(npos.y - 0.5) > 0.5) break;
				float tD = SampleDepth(npos, 0.5 * i) - 0.0001;
				float3 tVP = GetEyePos(npos, tD);
				float tA = dot(surfN, normalize(tVP - surfVP));
				
				
				
				maxP += 40.0 * saturate(tA) / length(surfVP);// / sqrt(1.0 + distance(tVP, surfVP));//RAY_LENGTH * tA / (1.0 + length(tVP - surfVP));
				
			}
			
			
			return saturate(maxP / 4.0);// * maxA.x;
		}
		
		float CalcTHICC(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			if( (FRAME_COUNT % 2) + (vpos.y + (vpos.x % 2)) % 2 == 0) discard;
			float3 surfN = GetNormal(xy);
			float  surfD = GetDepth(xy);
			
			
			float dir = 6.28 * IGN(vpos.xy + 5.588238  * ((FRAME_COUNT % 128) + 1));
		
			//float2 offset = float2(cos(dir), sin(dir)) / RES;
			
			#define HORIZONS 2
			
			float AOacc;
			for(int i = 1; i <= HORIZONS; i++)
			{
				
				float2 offset = float2(cos(dir), sin(dir)) / RES;
				//if(abs(xy.x + offset.x - 0.5) > 0.5 || abs(xy.y + offset.y - 0.5) > 0.5) break;
				//offset *= (1.0 - surfD);
				float jitter = IGN(vpos.xy + (i + 1) * 100.0);
				
				AOacc += TraceTHICC(xy, -surfN, surfD, offset, jitter);//countbits(~BITFIELD) / 32.0;
				
				dir += 6.28 / HORIZONS;
			}
			
			
			return (AOacc / HORIZONS);
		}
		
		//===================================================================================
		//Technique
		//===================================================================================
		
		
		technique Continuity <
		ui_label = "Quark: Continuity";
	    ui_tooltip =        
	        "								   Continuity - Made by Zenteon           \n"
	        "\n================================================================================================="
	        "\n"
	        "\nContinuity is a prepass shader meant to provide information to other shaders like MSRT"
	        "\n"
	        "\n=================================================================================================";
		>	
		{
			pass{ VertexShader = PostProcessVS; PixelShader = Down0;		RenderTarget = DownTex0; }
			pass{ VertexShader = PostProcessVS; PixelShader = Down1;		RenderTarget = DownTex1; }
			pass{ VertexShader = PostProcessVS; PixelShader = Up0;		  RenderTarget = DownTex0; }
			pass{ VertexShader = PostProcessVS; PixelShader = Up1;		  RenderTarget = Continuity::ColorTexture; }
		
			pass { VertexShader = PostProcessVS; PixelShader = LuminBuffer; RenderTarget = LumTex0; }
			pass { VertexShader = PostProcessVS; PixelShader = GenNorBuffer; RenderTarget0 = NorTex0; RenderTarget1 = HoleMask; }
			pass { VertexShader = PostProcessVS; PixelShader = FillNorBuffer; RenderTarget0 = NorTex1; RenderTarget1 = DepDerivTex; }
			pass { VertexShader = PostProcessVS; PixelShader = SmoothNormals0; RenderTarget = NorTex0; }
			pass { VertexShader = PostProcessVS; PixelShader = SmoothNormals1; RenderTarget = NorTex1; }
			pass { VertexShader = PostProcessVS; PixelShader = HeightNor; RenderTarget0 = NormalTexture; RenderTarget1 = NorTex0; }
			
			pass { VertexShader = PostProcessVS; PixelShader = SaveSamD; RenderTarget = DepSamTexture; }
			
			
			//pass { VertexShader = PostProcessVS; PixelShader = CalcTHICC; RenderTarget = ThickTexture; }
			
			pass { VertexShader = PostProcessVS; PixelShader = SaveSamN; RenderTarget = NorSamTexture; }
			
			/*pass
			{
				VertexShader = PostProcessVS;
				PixelShader = CNNormal;
			}*/
		}
		
	}
#else	
	int Dx9Warning <
		ui_type = "radio";
		ui_text = "Oops, looks like you're using DX9\n"
			"if you would like to use Quark Shaders in DX9 games, please use a wrapper like DXVK or dgVoodoo2";
		ui_label = " ";
		> = 0;
		
	technique Continuity <
	ui_label = "Quark: Continuity";
	    ui_tooltip =        
	        "								   Continuity - Made by Zenteon           \n"
	        "\n================================================================================================="
	        "\n"
	        "\nContinuity is a prepass shader meant to provide information to other shaders like MSRT"
	        "\n"
	        "\n=================================================================================================";
		>	
	{ }
#endif	
