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
	Quark: Fractal Grain v0.1 - Authored by Daniel Oren-Ibarra "Zenteon"
	
	Discord: https://discord.gg/PpbcqJJs6h
	Patreon: https://patreon.com/Zenteon


*/
//========================================================================

#include "ReShade.fxh"
#define CLAMPSAM AddressU = CLAMP; AddressV = CLAMP; AddressW = CLAMP
#define RES float2(BUFFER_WIDTH, BUFFER_HEIGHT)
#define LP (1.0 + (pow(1.0 - INTENSITY, 4.0) * 256.0))

uniform int FRAME_COUNT <
	source = "framecount";>;

#define FRAME_MOD ((!STATIC_GRN * FRAME_COUNT % 512) + (!STATIC_GRN * FRAME_COUNT % 512) + 1)


uniform float INTENSITY <
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_label = "Intensity";
> = 0.6;

uniform float GRAIN_SIZE <
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_label = "Grain Size\n\n";
> = 0.5;

uniform float IMG_SAT <
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_label = "Saturation";
> = 1.0;

uniform float GRAIN_SAT <
	ui_type = "slider";
	ui_min = 0.0;
	ui_max = 1.0;
	ui_label = "Grain Saturation";
> = 0.3;

uniform bool STATIC_GRN <
	ui_label = "Static Grain";
> = 1;

namespace FFG {
	texture GrainTex { Width = RES.x; Height = RES.y; Format = RGBA8; };
	sampler GrainSam { Texture = GrainTex; CLAMPSAM; };
	
	
	
	//=============================================================================
	//Functions
	//=============================================================================
	
	float4 UpSample(sampler input, float2 xy, float div, float offset)
	{
	    float2 hp =  0.65 / RES;
		float4 acc = 0.5 * tex2D(input, xy); 
	    
	    acc += 0.1875 * tex2Dlod(input, float4(xy - hp * offset, 0, 0));
	    acc += 0.1875 * tex2Dlod(input, float4(xy + hp * offset, 0, 0));
	    acc += 0.1875 * tex2Dlod(input, float4(xy + float2(hp.x, -hp.y) * offset, 0, 0));
	    acc += 0.1875 * tex2Dlod(input, float4(xy - float2(hp.x, -hp.y) * offset, 0, 0));
		
		acc += 0.0625 * tex2Dlod(input, float4(xy + hp * float2(2f, 0) * offset, 0, 0));
		acc += 0.0625 * tex2Dlod(input, float4(xy + hp * float2(-2f, 0) * offset, 0, 0));
		acc += 0.0625 * tex2Dlod(input, float4(xy + hp * float2(0, 2f) * offset, 0, 0));
		acc += 0.0625 * tex2Dlod(input, float4(xy + hp * float2(0, -2f) * offset, 0, 0));
	
	    return acc / 1.5;
	}
	
	
	float4 hash42(float2 inp)
	{
	    uint pg = asuint(RES.x * RES.x * inp.y + inp.x * RES.x);
	    uint state = pg * 747796405u + 2891336453u;
	    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	    uint4 RGBA = 0xFFu & word >> uint4(0,8,16,24); 
	    return float4(RGBA) / 0xFFu;
	}
	
	float4 lhash42(uint pg)
	{
	    uint state = pg * 747796405u + 2891336453u;
	    uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
	    uint4 RGBA = 0xFFu & word >> uint4(0,8,16,24); 
	    return float4(RGBA) / 0xFFu;
	}
	
	//=============================================================================
	//Passes
	//=============================================================================
	
	float4 GenGrain(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
	{
		float3 input = tex2D(ReShade::BackBuffer, texcoord).rgb;
		input = lerp(input.r * 0.2126 + input.g * 0.7152 + input.b * 0.0722, input, IMG_SAT);
		
		uint pg = uint(RES.x * RES.x * texcoord.y + texcoord.x * RES.x);
		float4 noise = lhash42((FRAME_MOD) * pg);
		noise.rgb = lerp(noise.a, noise.rgb, min(GRAIN_SAT, IMG_SAT));
		
		#define QuantBias ((pow(input, 1.3)) - 1f)
		input = floor(LP * (input + ((2.0 * noise.rgb + QuantBias) / LP))) / LP - ((noise.rgb - 0.5) / LP);
		input -= 0.15 * pow(INTENSITY, 4.0) * QuantBias;
		return float4(saturate(input), noise.a);
	}
	
	float3 QUARK_FILMGRAIN(float4 vpos : SV_Position, float2 texcoord : TexCoord) : SV_Target
	{
		float2 offset = GRAIN_SIZE * hash42(FRAME_MOD * texcoord + 0.5).zw / RES;
		float3 grain = UpSample(GrainSam, offset + texcoord, 1.0, 0.5 * GRAIN_SIZE).rgb;
		return grain;
	}
	
	technique Crystallis <
	ui_label = "Quark: Crystallis";
	    ui_tooltip =        
	        "								   Crystallis - Made by Zenteon           \n"
	        "\n================================================================================================="
	        "\n"
	        "\nCrystallis is a unique approach to filmgrain"
	        "\nbuilt around using quantization to simulate subpixel binaries"
	        "\n"
	        "\n=================================================================================================";
	>	
	{
		pass
		{
			VertexShader = PostProcessVS;
			PixelShader = GenGrain;
			RenderTarget = GrainTex;
		}
		pass
		{
			VertexShader = PostProcessVS;
			PixelShader = QUARK_FILMGRAIN;
		}
	}
}