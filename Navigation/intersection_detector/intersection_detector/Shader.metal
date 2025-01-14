//
//  Shader.metal
//  intersection_detector
//
//  Created by Masaki Kuribayashi on 2021/05/14.
//

#include <metal_stdlib>
#include <simd/simd.h>
#import "Shader.h"

using namespace metal;
constexpr sampler colorSampler(mip_filter::linear, mag_filter::linear, min_filter::linear);

constant auto yCbCrToRGB = float4x4(float4(+1.0000f, +1.0000f, +1.0000f, +0.0000f),
                                    float4(+0.0000f, -0.3441f, +1.7720f, +0.0000f),
                                    float4(+1.4020f, -0.7141f, +0.0000f, +0.0000f),
                                    float4(-0.7010f, +0.5291f, -0.8860f, +1.0000f));

bool shouldReturn (int gridWidth, int gridHeight, int thread_position_in_grid) {
    if (thread_position_in_grid % gridWidth == 0){ return true;}
    if (thread_position_in_grid % (gridWidth - 1) == 0){ return true;}
    if (thread_position_in_grid < gridWidth ){ return true;}
    if (thread_position_in_grid + gridWidth >= (gridHeight * gridWidth)) { return true;}
    return false;
}

// determine floor by relative height
kernel void computeFunction(constant PointCloudUniforms &uniforms [[ buffer(0) ]],
                            constant float2 *gridPoints [[ buffer(1) ]],
                            device simd_float3* outputData [[ buffer(2) ]],
                            device simd_float3* outputNormal [[ buffer(3) ]],
                            device simd_float4* outputGridInfo [[ buffer(4) ]],
                            texture2d<float, access::sample> depthTexture [[ texture(0) ]],
                            texture2d<unsigned int, access::sample> confidenceTexture [[texture(1)]],
                            uint thread_position_in_grid [[thread_position_in_grid]]) {
    
    if (shouldReturn(uniforms.gridWidth, uniforms.gridHeight, thread_position_in_grid)) { return ; }
    
    const auto gridPoint = gridPoints[thread_position_in_grid];
    const auto texCoord = gridPoint / uniforms.cameraResolution;
    const auto confidence = confidenceTexture.sample(colorSampler, texCoord).r;
    if (!(confidence >= uniforms.confidenceThreshold)){ return ;}
    if (texCoord.x > 0.97) { return ;}
    
    const auto depth = depthTexture.sample(colorSampler, texCoord).r;
    const auto cameraCoord = uniforms.cameraIntrinsicsInversed * simd_float3(gridPoint, 1) * depth;
    const auto worldPoint4 = uniforms.localToWorld * simd_float4(-cameraCoord.x,cameraCoord.y,-depth,1);
    const auto worldPoint = simd_float4(worldPoint4.x,worldPoint4.y,worldPoint4.z,1);
    
    const auto gridPointUp = gridPoints[thread_position_in_grid - uniforms.gridWidth];
    const auto gridPointDown = gridPoints[thread_position_in_grid + uniforms.gridWidth];
    const auto gridPointRight = gridPoints[thread_position_in_grid + 1];
    const auto gridPointLeft = gridPoints[thread_position_in_grid - 1];
    
    const auto texCoordUp = gridPointUp / uniforms.cameraResolution;
    const auto texCoordDown = gridPointDown / uniforms.cameraResolution;
    const auto texCoordRight = gridPointRight / uniforms.cameraResolution;
    const auto texCoordLeft = gridPointLeft / uniforms.cameraResolution;
    
    const auto depthUp = depthTexture.sample(colorSampler, texCoordUp).r;
    const auto depthDown = depthTexture.sample(colorSampler, texCoordDown).r;
    const auto depthRight = depthTexture.sample(colorSampler, texCoordRight).r;
    const auto depthLeft = depthTexture.sample(colorSampler, texCoordLeft).r;
    
    const auto pointUp = uniforms.cameraIntrinsicsInversed * simd_float3(gridPointUp, 1) * depthUp;
    const auto pointDown = uniforms.cameraIntrinsicsInversed * simd_float3(gridPointDown, 1) * depthDown;
    const auto pointRight = uniforms.cameraIntrinsicsInversed * simd_float3(gridPointRight, 1) * depthRight;
    const auto pointLeft = uniforms.cameraIntrinsicsInversed * simd_float3(gridPointLeft, 1) * depthLeft;
    
    const auto pointUp4 = uniforms.localToWorld * simd_float4(-pointUp.x,pointUp.y,-depthUp,1);
    const auto pointDown4 = uniforms.localToWorld * simd_float4(-pointDown.x,pointDown.y,-depthDown,1);
    const auto pointRight4 = uniforms.localToWorld * simd_float4(-pointRight.x,pointRight.y,-depthRight,1);
    const auto pointLeft4 = uniforms.localToWorld * simd_float4(-pointLeft.x,pointLeft.y,-depthLeft,1);

    const auto worldPointUp = simd_float3(pointUp4.x,-pointUp4.y,pointUp4.z);
    const auto worldPointDown = simd_float3(pointDown4.x,-pointDown4.y,pointDown4.z);
    const auto worldPointRight = simd_float3(pointRight4.x,-pointRight4.y,pointRight4.z);
    const auto worldPointLeft = simd_float3(pointLeft4.x,-pointLeft4.y,pointLeft4.z);
    
    simd_float3 vectorVertical = worldPointUp - worldPointDown;
    simd_float3 vectorHorizontal = worldPointLeft - worldPointRight;
    simd_float3 normal = normalize(cross(vectorVertical, vectorHorizontal));
    
    int gridX = round(worldPoint.x / uniforms.gridMapLength);
    int gridY = round(worldPoint.z / uniforms.gridMapLength);

    outputData[thread_position_in_grid] = worldPoint.xyz;
    outputNormal[thread_position_in_grid] = normal;
    
    float floorthreshold = 0.50;
    if (normal.y > uniforms.floorNormalY) { //up vector
        if ((abs(uniforms.floorHeight - worldPoint.y) < floorthreshold) && ( worldPoint.y < uniforms.currentHeight)) {
            outputGridInfo[thread_position_in_grid] = simd_float4(gridX,gridY,1,0); //floor
        } else {
            outputGridInfo[thread_position_in_grid] = simd_float4(gridX,gridY,0,1); //obstacle
        }
    } else if (normal.y < uniforms.ceilingNormalY) { //ceiling
        outputGridInfo[thread_position_in_grid] = simd_float4(gridX,gridY,0,0);
    } else { // not up vector (obstacle)
        outputGridInfo[thread_position_in_grid] = simd_float4(gridX,gridY,0,1); //obstacle
    }
}
