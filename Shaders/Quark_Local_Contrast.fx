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
	Quark: Local Contrast v0.1 - Authored by Daniel Oren-Ibarra "Zenteon"
	
	Discord: https://discord.gg/PpbcqJJs6h
	Patreon: https://patreon.com/Zenteon


*/
//========================================================================

#include "ReShade.fxh"

#define RES float2(BUFFER_WIDTH, BUFFER_HEIGHT)
#define FARPLANE RESHADE_DEPTH_LINEARIZATION_FAR_PLANE
#define ASPECT_RATIO (RES.x/RES.y)

#define DIVRES(DIVRES_RIV) Width = BUFFER_WIDTH / DIVRES_RIV; Height = BUFFER_HEIGHT / DIVRES_RIV



#if(__RENDERER__ != 0x9000)


	uniform int MODE <
		ui_type = "combo";
		ui_items = "Laplacian\0Unsharp\0Obscurance\0ZN LC\0Quark LC\0";
		ui_label = "Enhancement Mode";
		ui_tooltip = "Contrast enhancement method used.";
	> = 4;
	
	uniform float KERNEL_SHAPE <
		ui_type = "drag";
		ui_min = 0.0;
		ui_max = 1.0;
		ui_label = "Detail Precision";
		ui_tooltip = "Lower values effect larger sections of the image, higher values affect more details and have less clipping";
	> = 0.7;
	
	uniform float INTENSITY <
		ui_type = "drag";
		ui_min = -1.0;
		ui_max = 1.0;
		ui_label = "Intensity";
	> = 0.5;
	
	uniform float GLOBALBRIGHT <
		ui_type = "drag";
		ui_min = 0.0;
		ui_max = 1.0;
		ui_label = "Highlight Detail";
		ui_tooltip = "Enhances detail in brighter regions";
	> = 0.0;
	
	uniform int DEBUG <
		ui_type = "combo";
		ui_items = "None\0Image Difference\0Mask Difference\0";
		ui_label = "Debug";
	> = 0;
	
	namespace QLC0 {
		texture BlurTex0  { DIVRES(1); Format = R16; };
		texture BlurTex1  { DIVRES(1); Format = R16; };
		
		texture DownTex0 { DIVRES(2); Format = R16; };
		texture DownTex1 { DIVRES(4); Format = R16; };
		texture DownTex2 { DIVRES(8); Format = R16; };
		texture DownTex3 { DIVRES(16); Format = R16; };
		texture DownTex4 { DIVRES(32); Format = R16; };
		texture DownTex5 { DIVRES(64); Format = R16; };
		texture DownTex6 { DIVRES(128); Format = R16; };
	
		texture UpTex5 { DIVRES(64); Format = R16; };
		texture UpTex4 { DIVRES(32); Format = R16; };
		texture UpTex3 { DIVRES(16); Format = R16; };
		texture UpTex2 { DIVRES(8); Format = R16; };
		texture UpTex1 { DIVRES(4); Format = R16; };
		texture UpTex0 { DIVRES(2); Format = R16; };
	
		sampler BlurSam0  { Texture = BlurTex0;  };
		sampler BlurSam1  { Texture = BlurTex1;  };
		
		sampler DownSam0 { Texture = DownTex0; };
		sampler DownSam1 { Texture = DownTex1; };
		sampler DownSam2 { Texture = DownTex2; };
		sampler DownSam3 { Texture = DownTex3; };
		sampler DownSam4 { Texture = DownTex4; };
		sampler DownSam5 { Texture = DownTex5; };
		sampler DownSam6 { Texture = DownTex6; };
		
		sampler UpSam5 { Texture = UpTex5; };
		sampler UpSam4 { Texture = UpTex4; };
		sampler UpSam3 { Texture = UpTex3; };
		sampler UpSam2 { Texture = UpTex2; };
		sampler UpSam1 { Texture = UpTex1; };
		sampler UpSam0 { Texture = UpTex0; };
		
		//=============================================================================
		//Tonemappers
		//=============================================================================
		#define HDR_RED 1.05
		float3 Reinhardt(float3 x)
		{
			return HDR_RED * x / (x + 1.0);	
		}
		
		float3 IReinhardt(float3 x)
		{
			return -x / (x - HDR_RED);
		}
		
		//=============================================================================
		//Functions
		//=============================================================================
		#define OFF 1.0
		float DownSample(sampler input, float2 xy, float div)//0.375 + 0.25
		{
		    float2 hp = div * 0.5 / RES;
		    float offset = OFF;
		
		    float acc = 0.125 * tex2D(input, xy).r;
		    acc += 0.125 * tex2D(input, xy - hp * offset).r;
		    acc += 0.125 * tex2D(input, xy + hp * offset).r;
		    acc += 0.125 * tex2D(input, xy + float2(-hp.x, hp.y) * offset).r;
		    acc += 0.125 * tex2D(input, xy + float2(hp.x, -hp.y) * offset).r;
		    
		    acc += 0.0625 * tex2D(input, xy - float2(2f * hp.x, 0) * offset).r;
		    acc += 0.0625 * tex2D(input, xy + float2(0, 2f * hp.y) * offset).r;
		    acc += 0.0625 * tex2D(input, xy + float2(2f * -hp.x,0) * offset).r;
		    acc += 0.0625 * tex2D(input, xy - float2(0, 2f*-hp.y) * offset).r;
			
			acc += 0.03125 * tex2D(input, xy - hp * 2f * offset).r;
		    acc += 0.03125 * tex2D(input, xy + hp * 2f * offset).r;
		    acc += 0.03125 * tex2D(input, xy + float2(hp.x, -hp.y) * 2f * offset).r;
		    acc += 0.03125 * tex2D(input, xy - float2(hp.x, -hp.y) * 2f * offset).r;
	  
		    return acc;
		
		}
			
		float UpSample(sampler input, float2 xy, float div)
		{
		    float offset = OFF;
		    float2 hp =  div * 0.5 / RES;
			float acc = 0.5 * tex2D(input, xy).r; 
		    
		    acc += 0.1875 * tex2D(input, xy - hp * offset).r;
		    acc += 0.1875 * tex2D(input, xy + hp * offset).r;
		    acc += 0.1875 * tex2D(input, xy + float2(hp.x, -hp.y) * offset).r;
		    acc += 0.1875 * tex2D(input, xy - float2(hp.x, -hp.y) * offset).r;
		
		
		    return acc / 1.25;
		}
		
		float GetLum(float3 x)
		{
			if(MODE == 0) return dot(x, float3(0.2126, 0.7152, 0.0722));
			if(MODE == 2) return (x.r + x.g + x.b) / 3.0;
			if(MODE == 1) return dot(x, float3(0.2126, 0.7152, 0.0722));
			if(MODE == 3) return dot(x, float3(0.2126, 0.7152, 0.0722));
			if(MODE == 4) return dot(x, float3(0.2126, 0.7152, 0.0722));
			return 0.0;
		}
		
		//=============================================================================
		//Down Passes
		//=============================================================================
		float Lum(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			float3 col = tex2D(ReShade::BackBuffer, xy).rgb;
			col = GetLum(col);
			return col.r;
		}
		
		
		float Down0(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return DownSample(BlurSam0, xy, 2.0);
		}
		
		float Down1(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return DownSample(DownSam0, xy, 4.0);
		}
		
		float Down2(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return DownSample(DownSam1, xy, 8.0);
		}
		
		float Down3(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return DownSample(DownSam2, xy, 16.0);
		}
		
		float Down4(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return DownSample(DownSam3, xy, 32.0);
		}
		
		float Down5(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return DownSample(DownSam4, xy, 64.0);
		}
		
		float Down6(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return DownSample(DownSam5, xy, 128.0);
		}
		
		//=============================================================================
		//Up Passes
		//=============================================================================
		
		#define KS sqrt(1.0 - KERNEL_SHAPE)
		
		float Up5(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return lerp(tex2D(DownSam5, xy).r, UpSample(DownSam6, xy, 64.0), 0.3 + 0.7 * KS);
		}
		
		float Up4(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return lerp(tex2D(DownSam4, xy).r, UpSample(UpSam5, xy, 32.0), 0.4 + 0.6 * KS);
		}
		
		float Up3(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return lerp(tex2D(DownSam3, xy).r, UpSample(UpSam4, xy, 16.0), 0.5 + 0.5 * KS);
		}
		
		float Up2(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return lerp(tex2D(DownSam2, xy).r, UpSample(UpSam3, xy, 8.0), 0.6 + 0.4 * KS);
		}
		
		float Up1(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return lerp(tex2D(DownSam1, xy).r, UpSample(UpSam2, xy, 4.0), 0.7 + 0.3 * KS);
		}
		
		float Up0(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return lerp(tex2D(DownSam0, xy).r, UpSample(UpSam1, xy, 2.0), 0.8 + 0.2 * KS);
		}
		
		float Up00(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			return lerp(tex2D(BlurSam0, xy).r, UpSample(UpSam0, xy, 2.0), 0.9 + 0.1 * KS);
		}
		
		//=============================================================================
		//Blend Passes
		//=============================================================================
		
		
		float3 QuarkLC(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
		{
			float3 input = tex2D(ReShade::BackBuffer, xy).rgb;
			float lum = GetLum(input);
			float blum = UpSample(BlurSam0, xy, 2.0);
			
			input = IReinhardt(input);
			float blur = tex2D(BlurSam1, xy).r;
			float3 tempI = Reinhardt(input);
			
			float tempINT = INTENSITY;
			if(DEBUG) tempINT = 1.0;
			
			if(MODE == 0) input -= 3.0 * tempINT * input * (sqrt(blur) - sqrt(0.5 * lum + 0.5 * blum));
			if(MODE == 2) input *= lerp(1.0, (1.5 + pow(1.0 - KERNEL_SHAPE, 2.0)) * blur, 0.9 * tempINT);
			if(MODE == 3) input += pow(1.0 - blur, 0.5) * tempINT * (input - blur);
			
		
			
			//My fancy method
			if(MODE == 4) 
			{
				float3 detail = blur * (0.5 - pow(abs(blur - lum), 0.5) * sign(blur - lum));
				input = Reinhardt(input);
				float3 detail2 = input * (detail / blur);
				
				
				float3 screen = 1.0 - (1.0 - input) * (blur);
				detail = lerp(detail2, screen, input);
				input = lerp(input, detail, clamp(0.8 * tempINT, -0.8, 0.8));
			}
			else
			{
				input = Reinhardt(input);
			}
			
			
			
			if(MODE == 1) input = lerp(input * (1.0 - tempINT * blur), 1.0 - lerp(1.0, blur, tempINT) * (1.0 - input), pow(tempI, 2.2));
			
			
			
			input = pow(input, 1.0 + GLOBALBRIGHT * 0.5 * pow(lum, 2.0));
			if(DEBUG == 1) input = sqrt(2.0 * abs(input - INTENSITY * tempI));
			if(DEBUG == 2) input = sqrt(distance(INTENSITY * blur, input));
			
			return saturate(input - 0.001);
		}
		
		technique Quark_LC <
		ui_label = "Quark: Local Contrast";
		    ui_tooltip =        
		        "								   Quark LC - Made by Zenteon           \n"
		        "\n================================================================================================="
		        "\n"
		        "\nQuark LC is an all in one local contrast enhancement shader"
		        "\nIt features methods to enhance small scale details, highlights, and image graduation"
		        "\n"
		        "\n=================================================================================================";
		>	
		{
			pass {	VertexShader = PostProcessVS; PixelShader = Lum; RenderTarget0 = BlurTex0;} 
			pass {	VertexShader = PostProcessVS; PixelShader = Down0; RenderTarget = DownTex0; } 
			pass {	VertexShader = PostProcessVS; PixelShader = Down1; RenderTarget = DownTex1; }
			pass {	VertexShader = PostProcessVS; PixelShader = Down2; RenderTarget = DownTex2; } 
			pass {	VertexShader = PostProcessVS; PixelShader = Down3; RenderTarget = DownTex3; }
			pass {	VertexShader = PostProcessVS; PixelShader = Down4; RenderTarget = DownTex4; }
			pass {	VertexShader = PostProcessVS; PixelShader = Down5; RenderTarget = DownTex5; }
			pass {	VertexShader = PostProcessVS; PixelShader = Down6; RenderTarget = DownTex6; }
			
			pass {	VertexShader = PostProcessVS; PixelShader = Up5; RenderTarget = UpTex5;} 
			pass {	VertexShader = PostProcessVS; PixelShader = Up4; RenderTarget = UpTex4;} 
			pass {	VertexShader = PostProcessVS; PixelShader = Up3; RenderTarget = UpTex3;} 
			pass {	VertexShader = PostProcessVS; PixelShader = Up2; RenderTarget = UpTex2;}
			pass {	VertexShader = PostProcessVS; PixelShader = Up1; RenderTarget = UpTex1;} 
			pass {	VertexShader = PostProcessVS; PixelShader = Up0; RenderTarget = UpTex0; }
			pass {	VertexShader = PostProcessVS; PixelShader = Up00; RenderTarget = BlurTex1; }
			
			pass
			{
				VertexShader = PostProcessVS;
				PixelShader = QuarkLC;
			}
		}
	}
#else	
	int Dx9Warning <
		ui_type = "radio";
		ui_text = "Oops, looks like you're using DX9\n"
			"if you would like to use Quark Shaders in DX9 games, please use a wrapper like DXVK or dgVoodoo2";
		ui_label = " ";
		> = 0;
		
	technique Quark_LC <
		ui_label = "Quark: Local Contrast";
		    ui_tooltip =        
		        "								   Quark LC - Made by Zenteon           \n"
		        "\n================================================================================================="
		        "\n"
		        "\nQuark LC is an all in one local contrast enhancement shader"
		        "\nIt features methods to enhance small scale details, highlights, and image graduation"
		        "\n"
		        "\n=================================================================================================";
	>	
	{ }
#endif
