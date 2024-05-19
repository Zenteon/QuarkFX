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
	Quark: Xenon v0.1 - Authored by Daniel Oren-Ibarra
	
	Discord: https://discord.gg/PpbcqJJs6h
	Patreon: https://patreon.com/Zenteon


*/
//========================================================================

#include "ReShade.fxh"
#define WRAPSAM AddressU = CLAMP; AddressV = CLAMP; AddressW = CLAMP;

#ifndef Full_Control
//============================================================================================
	#define Full_Control 0
//============================================================================================
#endif

namespace Xenon {
	texture DirtTex < source = "QuarkDirt.png"; >
	{
		Width  = 1920;
		Height = 1080;
		Format = RGBA8;
	};
}

sampler XenDirt { Texture = Xenon::DirtTex; };

uniform int XENON <
	ui_type = "radio";
	ui_label = " ";
	ui_text = "XENON is a high quality bloom shader tuned to provide dramatic bloom without overpowering the image";
	ui_category = "XENON";
	ui_category_closed = true;
> = 0;

uniform float BLUR_OFFSET <
	ui_type = "slider";
	ui_min = 1.5;
	ui_max = 3.0;
	ui_label = "Bloom Radius";
> = 1.5;

uniform float BLOOM_INTENSITY <
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 1.0 + Full_Control;
	ui_label = "Bloom Intensity";
	ui_tooltip = "How much bloom is added into the original image";
> = 0.35;

uniform float BLOOM_BRIGHT <
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 2.0;
	ui_label = "Bloom Brightness";
	ui_tooltip = "Intensity of added bloom";
> = 1.0;

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
	ui_label = "Dirt Instensity";
> = 0.8;

uniform bool DEBUG <
	ui_label = "Display Raw Bloom\n\n";
	hidden = !Full_Control;
> = 0;

uniform float POSXPOS <
	ui_type = "slider";
	ui_min = 0.5;
	ui_max = 2.0;
	ui_label = "Post Contrast";
	hidden = !Full_Control;
	ui_tooltip = "Desaturates highlights and reduces point intensity";
> = 1.2;

uniform float PREXPOS <
	ui_type = "slider";
	ui_min = 0.9;
	ui_max = 2.0;
	ui_label = "Pre Exposure";
	hidden = !Full_Control;
	ui_tooltip = "Desaturates highlights and reduces point intensity";
> = 1.75;

uniform float3 BLOOM_COL <
	ui_type = "color";
	ui_label = "Bloom Color";
	hidden = !Full_Control;
> = 1.0;	

namespace XEN {
	texture LightMap{Width = BUFFER_WIDTH;	 Height = BUFFER_HEIGHT;	 Format = RGBA16F;};
	texture DownTex0{Width = BUFFER_WIDTH / 2; Height = BUFFER_HEIGHT / 2; Format = RGBA16F;};
	texture DownTex1{Width = BUFFER_WIDTH / 4; Height = BUFFER_HEIGHT / 4; Format = RGBA16F;};
	texture DownTex2{Width = BUFFER_WIDTH / 8; Height = BUFFER_HEIGHT / 8; Format = RGBA16F;};
	texture DownTex3{Width = BUFFER_WIDTH / 16; Height = BUFFER_HEIGHT / 16; Format = RGBA16F;};
	texture DownTex4{Width = BUFFER_WIDTH / 32; Height = BUFFER_HEIGHT / 32; Format = RGBA16F;};
	texture DownTex5{Width = BUFFER_WIDTH / 64; Height = BUFFER_HEIGHT / 64; Format = RGBA16F;};
	texture BloomTex{Width = BUFFER_WIDTH;	 Height = BUFFER_HEIGHT;	 Format = RGBA16F;};
}
sampler LightSam{Texture = XEN::LightMap; WRAPSAM};
sampler DownSam0{Texture = XEN::DownTex0; WRAPSAM};
sampler DownSam1{Texture = XEN::DownTex1; WRAPSAM};
sampler DownSam2{Texture = XEN::DownTex2; WRAPSAM};
sampler DownSam3{Texture = XEN::DownTex3; WRAPSAM};
sampler DownSam4{Texture = XEN::DownTex4; WRAPSAM};
sampler DownSam5{Texture = XEN::DownTex5; WRAPSAM};
sampler BloomSam{Texture = XEN::BloomTex; WRAPSAM};

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
    acc += 0.125 * tex2D(input, xy - hp * offset);
    acc += 0.125 * tex2D(input, xy + hp * offset);
    acc += 0.125 * tex2D(input, xy + float2(hp.x, -hp.y) * offset);
    acc += 0.125 * tex2D(input, xy - float2(hp.x, -hp.y) * offset);
    
    acc += 0.0625 * tex2D(input, xy - float2(2f * hp.x, 0) * offset);
    acc += 0.0625 * tex2D(input, xy + float2(0, 2f * hp.y) * offset);
    acc += 0.0625 * tex2D(input, xy + float2(2f * -hp.x,0) * offset);
    acc += 0.0625 * tex2D(input, xy - float2(0, 2f*-hp.y) * offset);
    
    acc += 0.03125 * tex2D(input, xy - hp * 2f * offset);
    acc += 0.03125 * tex2D(input, xy + hp * 2f * offset);
    acc += 0.03125 * tex2D(input, xy + float2(hp.x, -hp.y) * 2f * offset);
    acc += 0.03125 * tex2D(input, xy - float2(hp.x, -hp.y) * 2f * offset);
    
    

    return acc;

}

float4 UpSample(float2 xy, sampler input, float div)
{
	//float2 xy = texcoord;
	float2 res = float2(BUFFER_WIDTH, BUFFER_HEIGHT) / div;
    
    float offset = BLUR_OFFSET;
    float2 hp = 0.3 / res;
	float4 acc; 
    
    acc += 0.125 * tex2D(input, xy - hp * 2f * offset);
    acc += 0.125 * tex2D(input, xy + hp * 2f * offset);
    acc += 0.125 * tex2D(input, xy + float2(hp.x, -hp.y) * 2f * offset);
    acc += 0.125 * tex2D(input, xy - float2(hp.x, -hp.y) * 2f * offset);
	
	acc += 0.125 * tex2D(input, xy - hp * 2f * offset);
    acc += 0.125 * tex2D(input, xy + hp * 2f * offset);
    acc += 0.125 * tex2D(input, xy + float2(hp.x, -hp.y) * 2f * offset);
    acc += 0.125 * tex2D(input, xy - float2(hp.x, -hp.y) * 2f * offset);
	
    return acc;
}

//=============================================================================
//Tonemappers
//=============================================================================
#define HDR_RED 1.02
float3 ReinhardtJ(float3 x) //Modified Reinhardt Jodie
{
/*	
	float  lum = dot(x, float3(0.2126, 0.7152, 0.0722));
	float3 tx  = x / (x + 1.0);
	return HDR_RED * lerp(x / (lum + 1.0), tx, pow(tx, 0.7));
*/	
	return HDR_RED * x / (x + 1.0);
}

float3 InvReinhardtJ(float3 x)
{
/*
	float  lum = dot(x, float3(0.2126, 0.7152, 0.0722));
	float3 tx  = -x / (x - HDR_RED);
	return lerp(tx, -lum / ((0.5 * x + 0.5 * lum) - HDR_RED), pow(x, 0.7));
*/
	return max(-x / (x - HDR_RED), 0.0001);
}

//=============================================================================
//Passes
//=============================================================================
float4 BloomMap(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target
{
	float3 input	  = tex2D(ReShade::BackBuffer, xy).rgb;
	float  depth	  = 1f - ReShade::GetLinearizedDepth(xy);
	input = InvReinhardtJ(input);
	input = (normalize(input) / 0.5774) * pow((input.r + input.g + input.b) / 3.0, PREXPOS);
	return float4(BLOOM_COL * BLOOM_BRIGHT * input, depth);
}
//=============================================================================
//Bloom Passes
//=============================================================================

float4 DownSample0(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
	return DownSample(xy, LightSam, 2.0);	}

float4 UpSample0(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
	return UpSample(xy, DownSam0, 2.0);	}
//
float4 DownSample1(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
	return DownSample(xy, DownSam0, 4.0);	}

float4 UpSample1(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
	return UpSample(xy, DownSam1, 4.0);	}
//
float4 DownSample2(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
	return DownSample(xy, DownSam1, 8.0);	}

float4 UpSample2(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
	return UpSample(xy, DownSam2, 8.0);	}
//
float4 DownSample3(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
	return DownSample(xy, DownSam2, 16.0);	}

float4 UpSample3(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
	return UpSample(xy, DownSam3, 16.0);	}
//
float4 DownSample4(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
	return DownSample(xy, DownSam3, 32.0);	}

float4 UpSample4(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
	return UpSample(xy, DownSam4, 32.0);	}
//
float4 DownSample5(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
	return DownSample(xy, DownSam4, 64.0);	}

float4 UpSample5(float4 vpos : SV_Position, float2 xy : TexCoord) : SV_Target {
	return UpSample(xy, DownSam5, 64.0);	}
//

//=============================================================================
//Blending
//=============================================================================

float3 QUARK_BLOOM(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
{
	float  depth = 1f - ReShade::GetLinearizedDepth(texcoord);
	float3 input = tex2D(ReShade::BackBuffer, texcoord).rgb;
		   input = InvReinhardtJ(input);
	float2 res = float2(BUFFER_WIDTH, BUFFER_HEIGHT);
	float2 hp  = 0.25 / res;	   
		   float4 bloom =  0.25 * tex2D(LightSam, texcoord + float2(hp.x, hp.y));
		   	   bloom += 0.25 * tex2D(LightSam, texcoord + float2(hp.x, -hp.y));
		   	   bloom += 0.25 * tex2D(LightSam, texcoord + float2(-hp.x, -hp.y));
		   	   bloom += 0.25 * tex2D(LightSam, texcoord + float2(-hp.x, hp.y));

		   bloom += 1.0 * UpSample(texcoord, BloomSam, 1.0);
		   bloom += 0.95 * UpSample(texcoord, DownSam0, 2.0);
		   bloom += 0.5 * UpSample(texcoord, DownSam1, 4.0);
		   bloom += 0.35 * UpSample(texcoord, DownSam2, 8.0);
		   bloom += 0.25 * UpSample(texcoord, DownSam3, 16.0);
		   bloom += 0.25 * UpSample(texcoord, DownSam4, 32.0);
	
	
	bloom.rgb = pow(bloom.rgb / 4.75, 1.0 / PREXPOS);
	bloom = pow(bloom, POSXPOS);
	
	float4 dirt  = bloom * tex2D(XenDirt, texcoord);
	bloom = lerp(bloom, bloom + dirt, DIRT_STRENGTH);
	//bloom = bloom / pow(length(bloom), 0.15);//bloom = (normalize(bloom) / 0.33) * ((bloom.r + bloom.g + bloom.b) / 3.0);
	float mask = exp(-max(depth - tex2D(DownSam4, texcoord).a, 0.0) * DEPTH_MASK);
	
	input = lerp(input, bloom.rgb, mask * 0.25 * BLOOM_INTENSITY);
	
	
	if(DEBUG) return ReinhardtJ(mask * bloom.rgb);

	return ReinhardtJ(input);
}

technique Xenon <
ui_label = "Quark: Xenon";
    ui_tooltip =        
        "										Zenteon - Xenon Bloom            \n"
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
	pass {VertexShader = PostProcessVS; PixelShader = UpSample0;		  RenderTarget = XEN::BloomTex; }
	
	pass {VertexShader = PostProcessVS; PixelShader = DownSample1;		RenderTarget = XEN::DownTex1; }
	pass {VertexShader = PostProcessVS; PixelShader = UpSample1;		  RenderTarget = XEN::DownTex0; }
	
	pass {VertexShader = PostProcessVS; PixelShader = DownSample2;		RenderTarget = XEN::DownTex2; }
	pass {VertexShader = PostProcessVS; PixelShader = UpSample2;		  RenderTarget = XEN::DownTex1; }
				pass {VertexShader = PostProcessVS; PixelShader = DownSample3;		RenderTarget = XEN::DownTex3; }
	pass {VertexShader = PostProcessVS; PixelShader = UpSample3;		  RenderTarget = XEN::DownTex2; }
	
	pass {VertexShader = PostProcessVS; PixelShader = DownSample4;		RenderTarget = XEN::DownTex4; }
	pass {VertexShader = PostProcessVS; PixelShader = UpSample4;		  RenderTarget = XEN::DownTex3; }
	
	pass {VertexShader = PostProcessVS; PixelShader = DownSample5;		RenderTarget = XEN::DownTex5; }
	pass {VertexShader = PostProcessVS; PixelShader = UpSample5;		  RenderTarget = XEN::DownTex4; }
	
	pass
	{
		VertexShader = PostProcessVS;
		PixelShader = QUARK_BLOOM;
	}
}