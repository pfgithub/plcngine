#pragma ONCE

typedef struct cz_Bitmap3f cz_Bitmap3f;
typedef struct cz_Shape cz_Shape;

#ifdef MSDFGEN_IMPL_CPP

#define BODY(x) x

#include "msdfgen.h"
#include "ext/import-font.h"

using namespace msdfgen;

extern "C" {

struct cz_Bitmap3f {
    Bitmap<float, 3> instance;
};
struct cz_Shape {
    Shape instance;
};

#else

#define BODY(x) ;
typedef struct FreetypeHandle FreetypeHandle;
typedef struct FontHandle FontHandle;
typedef struct GlyphIndex GlyphIndex;
typedef struct Shape Shape;

#endif

FreetypeHandle* cz_initializeFreetype(void) BODY({
    return initializeFreetype();
})
void cz_deinitializeFreetype(FreetypeHandle* ft) BODY({
    return deinitializeFreetype(ft);
})
FontHandle* cz_loadFontData(FreetypeHandle* ft, byte* data, int length) BODY({
    return loadFontData(ft, data, length);
})
void cz_destroyFont(FontHandle* ft) BODY({
    return destroyFont(ft);
})
bool cz_loadGlyph(Shape* output, FontHandle* font, unicode_t unicode, double* advance) BODY({
    return loadGlyph(*output, font, unicode, advance);
})

#ifdef MSDFGEN_IMPL_CPP
cz_Bitmap3f* cz_createBitmap3f(int width, int height) {
    cz_Bitmap3f* result = new cz_Bitmap3f();
    result->instance = Bitmap<float, 3>(width, height);
    return result;
}
#else
cz_Bitmap3f* cz_createBitmap3f(int width, int height);
#endif
void cz_destroyBitmap3f(cz_Bitmap3f* bitmap) BODY({
    delete bitmap;
})
float* cz_bitmap3fPixels(cz_Bitmap3f* bitmap) BODY({
    return bitmap->instance; // Bitmap<T, N>::operator T *() :: implicit coersion
})
int cz_bitmap3fWidth(cz_Bitmap3f* bitmap) BODY({
    return bitmap->instance.width();
})
int cz_bitmap3fHeight(cz_Bitmap3f* bitmap) BODY({
    return bitmap->instance.height();
})

#ifdef MSDFGEN_IMPL_CPP
cz_Shape* cz_createShape() {
    return new cz_Shape();
}
#else
cz_Shape* cz_createShape();
})
#endif
void cz_destroyShape(cz_Shape* shape) BODY({
    delete shape;
})
void cz_shapeNormalize(cz_Shape* shape) BODY({
    shape->instance.normalize();
})

#if false
int main() BODY({
    FreetypeHandle *ft = initializeFreetype();
    if (ft) {
        FontHandle *font = loadFont(ft, "C:\\Windows\\Fonts\\arialbd.ttf");
        if (font) {
            Shape shape;
            if (loadGlyph(shape, font, 'A')) {
                shape.normalize();
                //                      max. angle
                edgeColoringSimple(shape, 3.0);
                //           image width, height
                Bitmap<float, 3> msdf(32, 32);
                //                     range, scale, translation
                generateMSDF(msdf, shape, 4.0, 1.0, Vector2(4.0, 4.0));
                savePng(msdf, "output.png");
            }
            destroyFont(font);
        }
        deinitializeFreetype(ft);
    }
    return 0;
})
#endif




#ifdef MSDFGEN_IMPL_CPP
}
#endif
