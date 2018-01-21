module gfx.core.typecons;

/// A transition from one state to another
struct Trans(T) {
    /// state before
    T from;
    /// state after
    T to;
}

/// Transition build helper
auto trans(T)(T from, T to) {
    return Trans!T(from, to);
}

/// template that resolves to true if an object of type T can be assigned to null
template isNullAssignable(T) {
    enum isNullAssignable =
        is(typeof((inout int = 0) {
            T t = T.init;
            t = null;
        }));
}

version(unittest) {
    private interface   ITest {}
    private class       CTest {}
    private struct      STest {}
    static assert( isNullAssignable!ITest);
    static assert( isNullAssignable!CTest);
    static assert(!isNullAssignable!STest);
    static assert( isNullAssignable!(STest*));
}

/// constructs an option from a value
Option!T some(T)(T val) {
    return Option!T(val);
}

/// symbolic value that constructs an Option in none state
enum none(T) = Option!(T).init;

/// Check that init value yields a none
unittest {
    auto vopt = none!int;
    assert(vopt.isNone);
    vopt = 12;
    assert(vopt.isSome);
    assert(vopt == 12);

    auto ropt = none!CTest;
    assert(ropt.isNone);
    assert(ropt._val is null);
    ropt = new CTest;
    assert(vopt.isSome);
}

auto option(R)(R input) if (isInputRange!R)
{
    alias T = ElementType!R;
    Option!T res;

    if (!input.empty) {
        res = input.front;
        input.popFront();
        assert(input.empty, "attempt to build Option with more than one element)");
    }

    return res;
}


struct Option(T)
{
    private T _val = T.init;

    static if (isNullAssignable!T) {
        this(inout T val) inout {
            _val = val;
        }

        @property bool isSome() const {
            return _val !is null;
        }

        @property bool isNone() const {
            return _val is null;
        }

        void setNone() {
            _val = null;
        }

        void opAssign()(T val) {
            _val = val;
        }
    }
    else {
        private bool _isSome    = false;

        this(inout T val) inout {
            _val = val;
            _isSome = true;
        }

        @property bool isSome() const {
            return _isSome;
        }

        @property bool isNone() const {
            return !_isSome;
        }

        void setNone() {
            .destroy(_val);
            _isSome = false;
        }

        void opAssign()(T val) {
            _val = val;
            _isSome = true;
        }
    }

    // casting to type that have implicit cast available (e.g Option!int to Option!uint)
    auto opCast(V : Option!U, U)() if (is(T : U)) {
        return Option!U(val_);
    }

    @property ref inout(T) get() inout @safe pure nothrow
    {
        enum message = "Called `get' on none Option!" ~ T.stringof ~ ".";
        assert(isSome, message);
        return _val;
    }

    template toString()
    {
        import std.format : FormatSpec, formatValue;
        // Needs to be a template because of DMD @@BUG@@ 13737.
        void toString()(scope void delegate(const(char)[]) sink, FormatSpec!char fmt)
        {
            if (isNull)
            {
                sink.formatValue("Option.none", fmt);
            }
            else
            {
                sink.formatValue(_value, fmt);
            }
        }

        // Issue 14940
        void toString()(scope void delegate(const(char)[]) @safe sink, FormatSpec!char fmt)
        {
            if (isNull)
            {
                sink.formatValue("Option.none", fmt);
            }
            else
            {
                sink.formatValue(_value, fmt);
            }
        }
    }

    // range interface

    @property bool empty() const {
        return isNone;
    }

    @property size_t length() const {
        return isSome ? 1 : 0;
    }

    @property void popFront() {
        setNone();
    }

    static if (isNullAssignable!T) {
        @property inout(T) front() inout {
            return get;
        }
    }
    else {
        @property T front() const {
            return get;
        }
    }

    @property Option!T save() {
        return isSome ? Option!T(_val) : none!T;
    }
}
