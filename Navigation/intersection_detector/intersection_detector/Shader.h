//
//  Shader.h
//  intersection_detector
//
//  Created by Masaki Kuribayashi on 2021/05/14.
//

#ifndef Shader_h
#define Shader_h

#include <simd/simd.h>

struct PointCloudUniforms {
    matrix_float4x4 localToWorld;
    matrix_float3x3 cameraIntrinsicsInversed;
    simd_float2 cameraResolution;
    unsigned int gridWidth;
    unsigned int gridHeight;
    unsigned int confidenceThreshold;
    float gridMapLength;
    float gridMapHeight;
    float floorHeight;
    float floorNormalY;
    float ceilingNormalY;
    float currentHeight;
};


#endif /* Shader_h */
