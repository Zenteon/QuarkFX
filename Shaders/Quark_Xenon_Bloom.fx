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
	Quark: Xenon v0.2 - Authored by Daniel Oren-Ibarra "Zenteon"
	
	Discord: https://discord.gg/PpbcqJJs6h
	Patreon: https://patreon.com/Zenteon


*/
//========================================================================





#if(__RENDERER__ != 0x9000)

	#include "ReShade.fxh"

	#ifndef FULL_CONTROL
	//============================================================================================
		#define FULL_CONTROL 0
	//============================================================================================
	#endif
	
	#ifndef EMX
	//============================================================================================
		#define EMX 0
	//============================================================================================
	#endif
	
	//#if(Sample_Wrap == 0)
	#define CLAMPSAM AddressU = CLAMP; AddressV = CLAMP; AddressW = CLAMP;
	#define WRAPSAM AddressU = WRAP; AddressV = WRAP; AddressW = WRAP;
	//#else
	//	#define WRAPSAM AddressU = WRAP; AddressV = WRAP; AddressW = WRAP;
	//#endif	
	#define RES float2(BUFFER_WIDTH, BUFFER_HEIGHT)
	#define ASPECT_R (float2(1.0, 0.5625) / float2(1.0, RES.y / RES.x))
	
	namespace Xenon {
		texture DirtTex < source = "QuarkDirt.png"; >
		{
			Width  = 1920;
			Height = 1080;
			Format = RGBA8;
		};
	}
	
	sampler XenDirt { Texture = Xenon::DirtTex; WRAPSAM};
	
	uniform int XENON <
		ui_type = "radio";
		ui_label = " ";
		ui_text = "XENON is a high quality bloom shader tuned to provide dramatic bloom without overpowering the image";
		ui_category = "XENON";
		ui_category_closed = true;
	> = 0;
	
	uniform float BLUR_OFFSET <
		ui_type = "slider";
		ui_min = 0.5;
		ui_max = 1.0;
		hidden = !FULL_CONTROL;
		ui_label = "Bloom Radius";
	> = 1.0;
	
	uniform float BLOOM_INTENSITY <
		ui_type = "slider";
		ui_min = 0.0;
		ui_max = 1.0 + FULL_CONTROL;
		ui_label = "Bloom Intensity";
		ui_tooltip = "How much bloom is added into the original image";
	> = 0.25;
	
	uniform float BLOOM_BRIGHT <
		ui_type = "slider";
		ui_min = 0.0;
		ui_max = 3.0;
		ui_label = "Bloom Brightness";
		ui_tooltip = "Intensity of added bloom";
	> = 1.5;
	
	uniform float DEPTH_MASK <
		ui_type = "slider";
		ui_min = 0.0;
		ui_max = 8.0;
		ui_label = "Depth Mask";
	> = 2.0;
	
	uniform float DIRT_STRENGTH <
		ui_type = "slider";
		ui_min = 0.0;
		ui_max = 2.0;
		ui_label = "Dirt Intensity";
	> = 0.8;
	
	uniform bool DEBUG <
		ui_label = "Display Raw Bloom\n\n";
		hidden = !FULL_CONTROL;
	> = 0;
	
	uniform float HDR_RED <
		ui_type = "slider";
		ui_min = 1.001;
		ui_max = 1.2;
		ui_label = "Range Expansion";
		hidden = !FULL_CONTROL;
		ui_tooltip = "Desaturates highlights and reduces point intensity";
	> = 1.03;
	
	uniform float POSXPOS <
		ui_type = "slider";
		ui_min = 0.5;
		ui_max = 2.0;
		ui_label = "Post Contrast";
		hidden = !FULL_CONTROL;
		ui_tooltip = "Desaturates highlights and reduces point intensity";
	> = 1.5;
	
	uniform float PREXPOS <
		ui_type = "slider";
		ui_min = 0.9;
		ui_max = 3.0;
		ui_label = "Pre Exposure";
		hidden = !FULL_CONTROL;
		ui_tooltip = "Desaturates highlights and reduces point intensity";
	> = 2.5;
	
	uniform float KERNEL_SHAPE <
		ui_type = "slider";
		ui_min = 0.1;
		ui_max = 1.0;
		ui_label = "Kernel Shape";
		hidden = !FULL_CONTROL;
		ui_tooltip = "Modify the shape of the bloom kernel";
	> = 0.7;
	
	uniform float BLOOM_SAT <
		ui_type = "slider";
		ui_min = 0.0;
		ui_max = 1.5;
		ui_label = "Bloom Saturation";
		hidden = !FULL_CONTROL;
	> = 1.1;
	
	uniform float3 BLOOM_COL <
		ui_type = "color";
		ui_label = "Bloom Color";
		hidden = !FULL_CONTROL;
	> = 1.0;	
	
	
	
	namespace XEN {
		texture LightMap{Width = BUFFER_WIDTH;	 Height = BUFFER_HEIGHT;	 Format = RGBA16F;};
		texture DownTex0{Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = RGBA16F;};
		texture DownTex1{Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = RGBA16F;};
		texture DownTex2{Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = RGBA16F;};
		texture DownTex3{Width = BUFFER_WIDTH / 16; Height = BUFFER_HEIGHT / 16; Format = RGBA16F;};
		texture DownTex4{Width = BUFFER_WIDTH / 32; Height = BUFFER_HEIGHT / 32; Format = RGBA16F;};
		texture DownTex5{Width = BUFFER_WIDTH / 64; Height = BUFFER_HEIGHT / 64; Format = RGBA16F;};
		texture DownTex6{Width = BUFFER_WIDTH / 128; Height = BUFFER_HEIGHT / 128; Format = RGBA16F;};
		texture DownTex7{Width = BUFFER_WIDTH / 256; Height = BUFFER_HEIGHT / 256; Format = RGBA16F;};
		
		texture UpTex000{Width = BUFFER_WIDTH / 128; Height = BUFFER_HEIGHT / 128; Format = RGBA16F;};
		texture UpTex00{Width = BUFFER_WIDTH / 64; Height = BUFFER_HEIGHT / 64; Format = RGBA16F;};
		texture UpTex0{Width = BUFFER_WIDTH / 32; Height = BUFFER_HEIGHT / 32; Format = RGBA16F;};
		texture UpTex1{Width = BUFFER_WIDTH / 16; Height = BUFFER_HEIGHT / 16; Format = RGBA16F;};
		texture UpTex2{Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = RGBA16F;};
		texture UpTex3{Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = RGBA16F;};
		texture UpTex4{Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = RGBA16F;};
		
		texture BloomTex{Width = BUFFER_WIDTH;	 Height = BUFFER_HEIGHT;	 Format = RGBA16F;};
	}
	sampler LightSam{Texture = XEN::LightMap; CLAMPSAM};
	sampler DownSam0{Texture = XEN::DownTex0; CLAMPSAM};
	sampler DownSam1{Texture = XEN::DownTex1; CLAMPSAM};
	sampler DownSam2{Texture = XEN::DownTex2; CLAMPSAM};
	sampler DownSam3{Texture = XEN::DownTex3; CLAMPSAM};
	sampler DownSam4{Texture = XEN::DownTex4; CLAMPSAM};
	sampler DownSam5{Texture = XEN::DownTex5; CLAMPSAM};
	sampler DownSam6{Texture = XEN::DownTex6; CLAMPSAM};
	sampler DownSam7{Texture = XEN::DownTex7; CLAMPSAM};
	
	sampler UpSam000{Texture = XEN::UpTex000; CLAMPSAM};
	sampler UpSam00{Texture = XEN::UpTex00; CLAMPSAM};
	sampler UpSam0{Texture = XEN::UpTex0; CLAMPSAM};
	sampler UpSam1{Texture = XEN::UpTex1; CLAMPSAM};
	sampler UpSam2{Texture = XEN::UpTex2; CLAMPSAM};
	sampler UpSam3{Texture = XEN::UpTex3; CLAMPSAM};
	sampler UpSam4{Texture = XEN::UpTex4; CLAMPSAM};
	
	
	sampler BloomSam{Texture = XEN::BloomTex; CLAMPSAM};
	
	//=============================================================================
	//Functions
	//=============================================================================
	
	float4 DownSample(float2 xy, sampler input, float div)//0.375 + 0.25
	{
		//float2 xy = texcoord;
		float2 res = float2(BUFFER_WIDTH, BUFFER_HEIGHT) / div;
	    float2 hp = 0.5 / res;
	    float offset = BLUR_OFFSET;
	
	    float4 acc = 0.125 * tex2D(input, xy);
	    acc += 0.125 * tex2D(input, xy + float2(hp.x, hp.y) * offset);
	    acc += 0.125 * tex2D(input, xy + float2(hp.x, -hp.y) * offset);
	    acc += 0.125 * tex2D(input, xy + float2(-hp.x, hp.y) * offset);
	    acc += 0.125 * tex2D(input, xy + float2(-hp.x, -hp.y) * offset);
	    
	    acc += 0.0625 * tex2D(input, xy + float2(2f * hp.x, 0) * offset);
	    acc += 0.0625 * tex2D(input, xy + float2(0, 2f * hp.y) * offset);
	    acc += 0.0625 * tex2D(input, xy + float2(2f * -hp.x,0) * offset);
	    acc += 0.0625 * tex2D(input, xy + float2(0, 2f*-hp.y) * offset);
	    
	    acc += 0.03125 * tex2D(input, xy + float2(hp.x, hp.y) * 2f * offset);
	    acc += 0.03125 * tex2D(input, xy + float2(hp.x, -hp.y) * 2f * offset);
	    acc += 0.03125 * tex2D(input, xy + float2(-hp.x, hp.y) * 2f * offset);
	    acc += 0.03125 * tex2D(input, xy + float2(-hp.x, -hp.y) * 2f * offset);
	
	  
	    return acc;
	
	}
	
	float4 UpSample(float2 xy, sampler input, float div)
	{
		//float2 xy = texcoord;
		float2 res = float2(BUFFER_WIDTH, BUFFER_HEIGHT) / div;
	    
	    float offset = BLUR_OFFSET;
	    float2 hp =  0.5 / res;
		float4 acc = 0.5 * tex2D(input, xy); 
	    
	    acc += 0.1875 * tex2D(input, xy + float2(hp.x, hp.y) * offset);
	    acc += 0.1875 * tex2D(input, xy + float2(hp.x, -hp.y) * offset);
	    acc += 0.1875 * tex2D(input, xy + float2(-hp.x, hp.y) * offset);
	    acc += 0.1875 * tex2D(input, xy + float2(-hp.x, -hp.y) * offset);
		
		acc += 0.0625 * tex2D(input, xy + hp * float2(2, 0) * offset);
		acc += 0.0625 * tex2D(input, xy + hp * float2(-2, 0) * offset);
		acc += 0.0625 * tex2D(input, xy + hp * float2(0, 2) * offset);
		acc += 0.0625 * tex2D(input, xy + hp * float2(0, -2) * offset);
	
	    return acc / 1.5;
	}
	
	//=============================================================================
	//Tonemappers
	//=============================================================================
	
	float3 ReinhardtJ(float3 x) //Modified Reinhardt Jodie
	{
		float  lum = dot(x, float3(0.2126, 0.7152, 0.0722));
		float3 tx  = x / (x + 1.0);
		return saturate(HDR_RED * lerp(x / (lum + 1.0), tx, pow(tx, 1.0)));
		//return saturate(HDR_RED * x / (x + 1.0));
	}
	
	float3 InvReinhardtJ(float3 x)
	{
	
		float  lum = dot(x, float3(0.2126, 0.7152, 0.0722));
		float3 tx  = -x / (x - HDR_RED);
		return max(lerp(tx, -lum / ((0.6 * x + 0.4 * lum) - HDR_RED), pow(x, 1.0)), 0.0001);
		//return max(-x / (x - HDR_RED), 0.0001);
	}
	
	//=============================================================================
	//Passes
	//=============================================================================
	float4 BloomMap(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
	{
		float3 input	  = tex2D(ReShade::BackBuffer, xy).rgb;
		float  depth	  = 1f - ReShade::GetLinearizedDepth(xy);
		input = InvReinhardtJ(input);
		input = lerp(0.2126 * input.r + 0.7152 * input.g + 0.0722 * input.b, input, BLOOM_SAT);
			  input = max(input, 0.0);
		input = (normalize(input) / 0.5774) * pow((input.r + input.g + input.b) / 3.0, PREXPOS);
		return float4(BLOOM_COL * BLOOM_BRIGHT * input, depth);
	}
	//=============================================================================
	//Bloom Passes
	//=============================================================================
	
	float4 DownSample0(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
		return DownSample(xy, LightSam, 2.0);	}
		
	float4 DownSample1(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
		return DownSample(xy, DownSam0, 4.0);	}
	
	float4 DownSample2(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
		return DownSample(xy, DownSam1, 8.0);	}
	
	float4 DownSample3(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
		return DownSample(xy, DownSam2, 16.0);	}
	
	float4 DownSample4(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
		return DownSample(xy, DownSam3, 32.0);	}
	
	float4 DownSample5(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
		return DownSample(xy, DownSam4, 64.0);	}
		
	float4 DownSample6(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
		return DownSample(xy, DownSam5, 128.0);	}
		
	float4 DownSample7(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
		return DownSample(xy, DownSam6, 256.0);	}
	//====
	
	float4 UpSample000(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
		return lerp(tex2D(DownSam6, xy), UpSample(xy, DownSam7, 256.0), 0.3 * KERNEL_SHAPE);	}
	
	float4 UpSample00(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
		return lerp(tex2D(DownSam5, xy), UpSample(xy, UpSam000, 128.0), 0.3 * KERNEL_SHAPE);	}
	
	float4 UpSample0(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
		return lerp(tex2D(DownSam4, xy), UpSample(xy, UpSam00, 64.0), 0.4 * KERNEL_SHAPE);	}
	
	float4 UpSample1(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
		return lerp(tex2D(DownSam3, xy), UpSample(xy, UpSam0, 32.0), 0.5 * KERNEL_SHAPE);	}
	
	float4 UpSample2(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
		return lerp(tex2D(DownSam2, xy), UpSample(xy, UpSam1, 16.0), 0.6 * KERNEL_SHAPE);	}
	
	float4 UpSample3(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
		return lerp(tex2D(DownSam1, xy), UpSample(xy, UpSam2, 8.0), 0.7 * KERNEL_SHAPE);	}
	
	float4 UpSample4(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
		return lerp(tex2D(DownSam0, xy), UpSample(xy, UpSam3, 4.0), 0.8 * KERNEL_SHAPE);	}
	
	float4 UpSample5(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
		return lerp(tex2D(LightSam, xy), UpSample(xy, UpSam4, 2.0), 0.9 * KERNEL_SHAPE);	}
	
	//=============================================================================
	//Blending
	//=============================================================================
	
	float3 QUARK_BLOOM(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
	{
		float  depth = 1f - ReShade::GetLinearizedDepth(texcoord);
		float3 input = tex2D(ReShade::BackBuffer, texcoord).rgb;
			   input = InvReinhardtJ(input);
		
		float4 bloom =  UpSample(texcoord, BloomSam, 1.0);
		
		bloom.rgb = pow(bloom.rgb / 4.75, 1.0 / PREXPOS);
		bloom.rgb = pow(bloom.rgb, POSXPOS);
		
		float4 dirt  = bloom * tex2D(XenDirt, ASPECT_R * texcoord);
		bloom.rgb = lerp(bloom.rgb, bloom.rgb + dirt.rgb, DIRT_STRENGTH);
	
		float mask = exp(-max(depth - UpSample(texcoord, UpSam0, 32.0).a, 0.0) * DEPTH_MASK);
		
		input = lerp(input, bloom.rgb, mask * 0.3 * BLOOM_INTENSITY);
		
		
		if(DEBUG) return ReinhardtJ(mask * bloom.rgb);
	
		return ReinhardtJ(input);
	}
	
	technique Xenon <
	ui_label = "Quark: Xenon";
	    ui_tooltip =        
	        "								   Xenon Bloom - Made by Zenteon           \n"
	        "\n================================================================================================="
	        "\n"
	        "\nXenon is a high quality artistic bloom."
	        "\nIt features a uniquely shaped kernel to balance between wide bloom ranges and excellent precision"
	        "\nwithout completely overpowering the image"
	        "\n"
	        "\n=================================================================================================";
	>	
	{
		pass
		{
			VertexShader = PostProcessVS;
			PixelShader = BloomMap;
			RenderTarget = XEN::LightMap; 
		}
		
		pass {VertexShader = PostProcessVS; PixelShader = DownSample0;		RenderTarget = XEN::DownTex0; }
		pass {VertexShader = PostProcessVS; PixelShader = DownSample1;		RenderTarget = XEN::DownTex1; }
		pass {VertexShader = PostProcessVS; PixelShader = DownSample2;		RenderTarget = XEN::DownTex2; }
		pass {VertexShader = PostProcessVS; PixelShader = DownSample3;		RenderTarget = XEN::DownTex3; }
		pass {VertexShader = PostProcessVS; PixelShader = DownSample4;		RenderTarget = XEN::DownTex4; }
		pass {VertexShader = PostProcessVS; PixelShader = DownSample5;		RenderTarget = XEN::DownTex5; }
		pass {VertexShader = PostProcessVS; PixelShader = DownSample6;		RenderTarget = XEN::DownTex6; }
		pass {VertexShader = PostProcessVS; PixelShader = DownSample7;		RenderTarget = XEN::DownTex7; }
		
		pass {VertexShader = PostProcessVS; PixelShader = UpSample000;		RenderTarget = XEN::UpTex000; }
		pass {VertexShader = PostProcessVS; PixelShader = UpSample00;		RenderTarget = XEN::UpTex00; }
		pass {VertexShader = PostProcessVS; PixelShader = UpSample0;		RenderTarget = XEN::UpTex0; }
		pass {VertexShader = PostProcessVS; PixelShader = UpSample1;		RenderTarget = XEN::UpTex1; }
		pass {VertexShader = PostProcessVS; PixelShader = UpSample2;		RenderTarget = XEN::UpTex2; }
		pass {VertexShader = PostProcessVS; PixelShader = UpSample3;		RenderTarget = XEN::UpTex3; }
		pass {VertexShader = PostProcessVS; PixelShader = UpSample4;		RenderTarget = XEN::UpTex4; }
		pass {VertexShader = PostProcessVS; PixelShader = UpSample5;		RenderTarget = XEN::BloomTex; }
		pass
		{
			VertexShader = PostProcessVS;
			PixelShader = QUARK_BLOOM;
		}
	}
#else	
	int Dx9Warning <
		ui_type = "radio";
		ui_text = "Oops, looks like you're using DX9\n"
			"if you would like to use Quark Shaders in DX9 games, please use a wrapper like DXVK or dgVoodoo2";
		ui_label = " ";
		> = 0;
		
	technique Xenon <
	ui_label = "Quark: Xenon";
	    ui_tooltip =        
	        "								   Xenon Bloom - Made by Zenteon           \n"
	        "\n================================================================================================="
	        "\n"
	        "\nXenon is a high quality artistic bloom."
	        "\nIt features a uniquely shaped kernel to balance between wide bloom ranges and excellent precision"
	        "\nwithout completely overpowering the image"
	        "\n"
	        "\n=================================================================================================";
	>	
	{ }
#endif
