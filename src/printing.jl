"""
    print_tree(tree; kwargs...)
    print_tree(io::IO, tree; kwargs...)
    print_tree(f::Function, io::IO, tree; kwargs...)

Print a text representation of `tree` to the given `io` object.

# Arguments

* `f::Function` - custom implementation of [`printnode`](@ref) to use. Should have the
  signature `f(io::IO, node)`.
* `io::IO` - IO stream to write to.
* `tree` - tree to print.
* `maxdepth::Integer = 5` - truncate printing of subtrees at this depth.
* `indicate_truncation::Bool = true` - print a vertical ellipsis character beneath
  truncated nodes.
* `charset::TreeCharSet` - [`TreeCharSet`](@ref) to use to print branches.
* `printkeys::Union{Bool, Nothing}` - Whether to print keys of child nodes (using
  `pairs(children(node))`). A value of `nothing` uses [`printkeys_default`](@ref) do decide the
  behavior on a node-by-node basis.

# Examples

```julia
julia> tree = [1:3, "foo", [[[4, 5], 6, 7], 8]];

julia> print_tree(tree)
Vector{Any}
├─ UnitRange{Int64}
│  ├─ 1
│  ├─ 2
│  └─ 3
├─ "foo"
└─ Vector{Any}
   ├─ Vector{Any}
   │  ├─ Vector{Int64}
   │  │  ├─ 4
   │  │  └─ 5
   │  ├─ 6
   │  └─ 7
   └─ 8

julia> print_tree(tree, maxdepth=2)
Vector{Any}
├─ UnitRange{Int64}
│  ├─ 1
│  ├─ 2
│  └─ 3
├─ "foo"
└─ Vector{Any}
   ├─ Vector{Any}
   │  ⋮
   │
   └─ 8

julia> print_tree(tree, charset=AbstractTrees.ASCII_CHARSET)
Vector{Any}
+-- UnitRange{Int64}
|   +-- 1
|   +-- 2
|   \\-- 3
+-- "foo"
\\-- Vector{Any}
    +-- Vector{Any}
    |   +-- Vector{Int64}
    |   |   +-- 4
    |   |   \\-- 5
    |   +-- 6
    |   \\-- 7
    \\-- 8
```

"""
function print_tree end


"""
    printnode(io::IO, node)

Print a compact representation of a single node.  By default, this prints `nodevalue(node)`.

**OPTIONAL**: This can be extended for custom types and controls how nodes are shown
in [`print_tree`](@ref).
"""
printnode(io::IO, node) = show(IOContext(io, :compact => true, :limit => true), nodevalue(node))


"""
    repr_node(node; context=nothing)

Get the string representation of a node using [`printnode`](@ref). This works
analagously to `Base.repr`.

`context` is an `IO` or `IOContext` object whose attributes are used for the
I/O stream passed to `printnode`.
"""
function repr_node(node; context=nothing)
    buf = IOBuffer()
    io = context === nothing ? buf : IOContext(buf, context)
    printnode(io, node)
    return String(take!(buf))
end


const CharArg = Union{AbstractString, Char}

"""
    TreeCharSet(mid, terminator, skip, dash, trunc, pair)

Set of characters (or strings) used to pretty-print tree branches in [`print_tree`](@ref).

## Fields
- `mid`: "Forked" branch segment connecting to middle children.
- `terminator`: Final branch segment connecting to last child.
- `skip`: Vertical branch segment.
- `dash`: Horizontal branch segmentt printed to the right of `mid` and `terminator`.
- `trunc`: Used to indicate the subtree has been truncated at the maximum depth.
- `pair`: Printed between a child node and its key.
"""
struct TreeCharSet
    mid::String
    terminator::String
    skip::String
    dash::String
    trunc::String
    pair::String

    function TreeCharSet(mid::CharArg, terminator::CharArg, skip::CharArg, dash::CharArg, trunc::CharArg, pair::CharArg)
        return new(String(mid), String(terminator), String(skip), String(dash), String(trunc), String(pair))
    end
end

"""
    TreeCharSet(base::TreeCharSet; fields...)

Create a new `TreeCharSet` by modifying select fields of an existing instance.
"""
function TreeCharSet(base::TreeCharSet;
                     mid = base.mid,
                     terminator = base.terminator,
                     skip = base.skip,
                     dash = base.dash,
                     trunc = base.trunc,
                     pair = base.pair,
                    )
    return TreeCharSet(mid, terminator, skip, dash, trunc, pair)
end

"""
    TreeCharSet(name=:unicode)

Generate one of the default tree character sets.  Valid options are `:unicode` (default) and `:ascii`.
"""
function TreeCharSet(name::Symbol=:unicode)
    if name == :unicode
        TreeCharSet("├", "└", "│", "─", "⋮", " ⇒ ")
    elseif name == :ascii
        TreeCharSet("+", "\\", "|", "--", "...", " => ")
    else
        throw(ArgumentError("unrecognized dfeault TreeCharSet name: $name"))
    end
end

"""
    shouldprintkeys(children)::Bool

Whether a collection of children should be printed with its keys by default.

The base behavior is to print keys for all collections for which `keys()` is defined, with the
exception of `AbstractVector`s and tuples.
"""
shouldprintkeys(ch) = applicable(keys, ch)
shouldprintkeys(::AbstractVector) = false
shouldprintkeys(::Tuple) = false
shouldprintkeys(::Base.Generator) = false


"""
    print_child_key(io::IO, key)

Print the key for a child node.
"""
print_child_key(io::IO, key) = show(io, key)
print_child_key(io::IO, key::CartesianIndex) = show(io, Tuple(key))

branchwidth(cs::TreeCharSet) = sum(textwidth.((cs.mid, cs.dash)))

function print_tree(printnode::Function, io::IO, node;
                    maxdepth::Integer=5,
                    indicate_truncation::Bool=true,
                    charset::TreeCharSet=TreeCharSet(),
                    printkeys::Union{Bool,Nothing}=nothing,
                    depth::Integer=0,
                    prefix::AbstractString="",
                   )
    # Get node representation as string
    str = repr_node(node, context=io)

    # Copy buffer to output, prepending prefix to each line
    for (i, line) in enumerate(split(str, '\n'))
        i ≠ 1 && print(io, prefix)
        println(io, line)
    end

    # Node children
    c = children(node)

    # No children?
    isempty(c) && return

    # Reached max depth?
    if depth ≥ maxdepth
        # Print truncation char(s)
        if indicate_truncation
            println(io, prefix, charset.trunc)
            println(io, prefix)
        end
        return
    end

    # Print keys?
    this_printkeys = applicable(keys, c) && (isnothing(printkeys) ? shouldprintkeys(c) : printkeys)

    # Print children
    s = Iterators.Stateful(this_printkeys ? pairs(c) : c)

    while !isempty(s)
        child_prefix = prefix

        if this_printkeys
            child_key, child = popfirst!(s)
        else
            child = popfirst!(s)
            child_key = nothing
        end

        print(io, prefix)

        # Last child?
        if isempty(s)
            print(io, charset.terminator)
            child_prefix *= " " ^ (textwidth(charset.skip) + textwidth(charset.dash) + 1)
        else
            print(io, charset.mid)
            child_prefix *= charset.skip * " " ^ (textwidth(charset.dash) + 1)
        end

        print(io, charset.dash, ' ')

        # Print key
        if this_printkeys
            buf = IOBuffer()
            print_child_key(IOContext(buf, io), child_key)
            key_str = String(take!(buf))

            print(io, key_str, charset.pair)

            child_prefix *= " " ^ (textwidth(key_str) + textwidth(charset.pair))
        end

        print_tree(printnode, io, child;
                   maxdepth, indicate_truncation, charset, printkeys,
                   depth=depth+1, prefix=child_prefix
                  )
    end
end

print_tree(io::IO, node; kw...) = print_tree(printnode, io, node; kw...)
print_tree(node; kw...) = print_tree(stdout, node; kw...)


"""
    repr_tree(tree; context=nothing, kw...)

Get the string result of calling [`print_tree`](@ref) with the supplied arguments.

The `context` argument works as it does in `Base.repr`.
"""
function repr_tree(tree; context=nothing, kw...)
    buf = IOBuffer()
    io = context === nothing ? buf : IOContext(buf, context)
    print_tree(io, tree; kw...)
    return String(take!(buf))
end
