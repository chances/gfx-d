module gfx.device.gl3.state;

import gfx.foundation.typecons : Option;
import gfx.pipeline.state :     Rasterizer, FrontFace, CullFace, RasterMethod, Offset,
                            Blend, Equation, Factor, ColorFlags;
import gfx.pipeline.pso : ColorInfo;

import derelict.opengl3.gl3;


GLenum frontFaceToGl(in FrontFace ff) {
    final switch(ff) {
        case FrontFace.cw: return GL_CW;
        case FrontFace.ccw: return GL_CCW;
    }
}

GLenum equationToGl(in Equation eq) {
    final switch(eq) {
        case Equation.add:      return GL_FUNC_ADD;
        case Equation.sub:      return GL_FUNC_SUBTRACT;
        case Equation.revSub:   return GL_FUNC_REVERSE_SUBTRACT;
        case Equation.min:      return GL_MIN;
        case Equation.max:      return GL_MAX;
    }
}



GLenum factorToGl(in Factor f) {
    final switch (f) {
        case Factor.zero:               return GL_ZERO;
        case Factor.one:                return GL_ONE;
        case Factor.srcAlphaSaturated:  return GL_SRC_ALPHA_SATURATE;

        case Factor.zeroPlusSrcColor:   return GL_SRC_COLOR;
        case Factor.zeroPlusSrcAlpha:   return GL_SRC_ALPHA;
        case Factor.zeroPlusDestColor:  return GL_DST_COLOR;
        case Factor.zeroPlusDestAlpha:  return GL_DST_ALPHA;
        case Factor.zeroPlusConstColor: return GL_CONSTANT_COLOR;
        case Factor.zeroPlusConstAlpha: return GL_CONSTANT_ALPHA;

        case Factor.oneMinusSrcColor:   return GL_ONE_MINUS_SRC_COLOR;
        case Factor.oneMinusSrcAlpha:   return GL_ONE_MINUS_SRC_ALPHA;
        case Factor.oneMinusDestColor:  return GL_ONE_MINUS_DST_COLOR;
        case Factor.oneMinusDestAlpha:  return GL_ONE_MINUS_DST_ALPHA;
        case Factor.oneMinusConstColor: return GL_ONE_MINUS_CONSTANT_COLOR;
        case Factor.oneMinusConstAlpha: return GL_ONE_MINUS_CONSTANT_ALPHA;
    }
}


void setRasterMethod(in RasterMethod method, in Option!Offset offset) {
    void doit(GLenum polygonMode, GLenum glOffset) {
        glPolygonMode(GL_FRONT_AND_BACK, polygonMode);
        if (offset.isNone) {
            glDisable(glOffset);
        }
        else {
            glPolygonOffset(offset.get.slope, offset.get.units);
            glEnable(glOffset);

        }
    }

    final switch(method.tag) {
        case RasterMethod.Point:
            doit(GL_POINT, GL_POLYGON_OFFSET_POINT);
            break;
        case RasterMethod.Line:
            glLineWidth(method.getLine());
            doit(GL_LINE, GL_POLYGON_OFFSET_LINE);
            break;
        case RasterMethod.Fill:
            doit(GL_FILL, GL_POLYGON_OFFSET_FILL);
            break;
    }
}

void setRasterizer(in Rasterizer rasterizer) {
    glFrontFace(frontFaceToGl(rasterizer.frontFace));

    final switch (rasterizer.cullFace) {
        case CullFace.none:
            glDisable(GL_CULL_FACE);
            break;
        case CullFace.front:
            glEnable(GL_CULL_FACE);
            glCullFace(GL_FRONT);
            break;
        case CullFace.back:
            glEnable(GL_CULL_FACE);
            glCullFace(GL_BACK);
            break;
    }

    setRasterMethod(rasterizer.method, rasterizer.offset);

    if (rasterizer.samples) {
        glEnable(GL_MULTISAMPLE);
    }
    else {
        glDisable(GL_MULTISAMPLE);
    }
}


void bindBlend(in ColorInfo info) {
    if (info.blend.isSome) {
        glEnable(GL_BLEND);
        glBlendEquationSeparate(
            equationToGl(info.blend.get.color.equation),
            equationToGl(info.blend.get.alpha.equation),
        );
        glBlendFuncSeparate(
            factorToGl(info.blend.get.color.source),
            factorToGl(info.blend.get.color.destination),
            factorToGl(info.blend.get.alpha.source),
            factorToGl(info.blend.get.alpha.destination),
        );
    }
    else {
        glDisable(GL_BLEND);
    }
    glColorMask(
        (info.mask & ColorFlags.red) ? GL_TRUE : GL_FALSE,
        (info.mask & ColorFlags.green) ? GL_TRUE : GL_FALSE,
        (info.mask & ColorFlags.blue) ? GL_TRUE : GL_FALSE,
        (info.mask & ColorFlags.alpha) ? GL_TRUE : GL_FALSE,
    );
}


void bindBlendSlot(ColorInfo info, ubyte slot) {
    immutable buf = GLuint(slot);
    if (info.blend.isSome) {
        glEnablei(GL_BLEND, buf);
        glBlendEquationSeparateiARB(buf,
            equationToGl(info.blend.get.color.equation),
            equationToGl(info.blend.get.alpha.equation),
        );
        glBlendFuncSeparateiARB(buf,
            factorToGl(info.blend.get.color.source),
            factorToGl(info.blend.get.color.destination),
            factorToGl(info.blend.get.alpha.source),
            factorToGl(info.blend.get.alpha.destination),
        );
    }
    else {
        glDisablei(GL_BLEND, buf);
    }
    glColorMaski(buf,
        (info.mask & ColorFlags.red) ? GL_TRUE : GL_FALSE,
        (info.mask & ColorFlags.green) ? GL_TRUE : GL_FALSE,
        (info.mask & ColorFlags.blue) ? GL_TRUE : GL_FALSE,
        (info.mask & ColorFlags.alpha) ? GL_TRUE : GL_FALSE,
    );
}