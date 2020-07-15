#include <metal_stdlib>
using namespace metal;

typedef struct {
    float4 renderedCoordinate [[position]];
    float2 textureCoordinate;
} TextureMappingVertex;

vertex TextureMappingVertex mapTexture(unsigned int vertex_id [[ vertex_id ]]) {
    float4x4 renderedCoordinates = float4x4(float4( -1.0, -1.0, 0.0, 1.0 ),      /// (x, y, depth, W)
                                            float4(  1.0, -1.0, 0.0, 1.0 ),
                                            float4( -1.0,  1.0, 0.0, 1.0 ),
                                            float4(  1.0,  1.0, 0.0, 1.0 ));

    float4x2 textureCoordinates = float4x2(float2( 0.0, 1.0 ), /// (x, y)
                                           float2( 1.0, 1.0 ),
                                           float2( 0.0, 0.0 ),
                                           float2( 1.0, 0.0 ));
    TextureMappingVertex outVertex;
    outVertex.renderedCoordinate = renderedCoordinates[vertex_id];
    outVertex.textureCoordinate = textureCoordinates[vertex_id];
    
    return outVertex;
}

fragment float4 displayTexture(TextureMappingVertex mappingVertex [[ stage_in ]],
                               texture2d<float, access::sample> camera [[ texture(0) ]],
                               texture2d<float, access::sample> blur [[ texture(1) ]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float2 offset = mappingVertex.textureCoordinate;
    float2 normalizedOffet = float2(offset.x * camera.get_width() / camera.get_height(), offset.y);
    if (distance(float2(0.5, 0.5), normalizedOffet) > 0.3) {
        return blur.sample(s, offset);
    } else {
        return camera.sample(s, offset);
    }
}
