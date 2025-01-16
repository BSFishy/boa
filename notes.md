# notes

here are some general notes that i have about the language, language design,
standard library, etc.

i feel like a big thing driving the design of the language is decoupling
functionality and data, but still allowing for a relationship between data and
functionality.

## postfix/paths

in boa, paths are separated with `#`. since they aren't separated by `.`,
postfix is able to be done really easily. it can look like
`data.namespace#function()`, which is equivalent to `namespace#function(data)`.
this scales with multiple arguments, where `data.namespace#function(arg1, arg2)`
maps to `namespace#function(data, arg1, arg2)`.

this makes chaining postfix super easy, so it can be writtin as follows

```text
data
  .namespace1#function1()
  .namespace1#function2()
  .namespace2#function1()
  .namespace2#function2()
```

need to figure out if accessing struct fields should use the `#` syntax or if
it should be the `.` syntax.

## top-level structures

i'm still working through how i want this. i like the way zig does it, where
importing is done as a variable declaration, as is struct definitions. trying
to figure out if i also want to do the same with function definitions. i feel
like it may actually kinda be nice, since it will vastly simplify the syntax of
top-level structures. you may only use const variable declarations.

the main thing i'm thinking is going to require deeper thinking is name
mangling. embedding functions within functions is something that should be
pretty easy to do, so long as we properly mangle it. additionally, we should
allow for function name overflowing, again, so long as we properly mangle the
names. although function name overflowing is a separate design discussion.

## multiple return values

an important thing is going to be multiple return values/error and nullable
types. the big thing here is how it will integrate with the postfix syntax.
this is an unanswered design discussion, although i have a few ideas.

for error types, assuming we go with zig-style errors, we could propagate with
a postfix `?` operator:

```text
data
  .namespace#errorable_function()?
  .namespace#function2()
```

although i think we should also be able to pass around errorable values so that
we could do custom stuff with it like this:

```text
data
  .namespace#errorable_function()
  .namespace#map_error(
    fn(value: Data) void { core#print("valid data: %", .{value}); },
    fn(err: error) void { core#print("errored: %", .{err}); },
  )
```

probably similar thing with errorable. maybe it's not soo undefined, but still
want to put more though and testing into it to make sure this will be a good way
to go about things.

the thing we need to worry about, though, is functions that allocate but want
to return data. for example, if i have a function that creates an array list,
fills it with some data, then returns a view into that array list, it should
return the array list to be deallocated so that when we use the data it still
exists, but in postfix chaining we want to actually use the view. will probably
need to invent some syntax or research certain lifetime designs to achieve this.

maybe if we allocate in a function and need to return that allocation, do
nothing. the caller will need to deallocate that data anyway, so they will need
to handle it how they handle it. no postfix chaining at the end or anything, no
new syntax. keep things simple, if you allocate and return the allocation, you
must handle the deallocation associated with it, and you may use the data later
if you wish. short and simple.

## api levels

so i want to go about api levels in a similar way to odin. i want to have
builtins, core, and vendor, as well as install modules from git/tarball/etc.

the main apis, though, are brought by the default toolchain. they are as follows:

1. `builtins` - these are functions built into to compiler. generally speaking,
   they compile into certain instructions or other basic function calls, that
   otherwise don't have syntax. they are paths without a namespace, and look
   like the following: `#saturating_add(...)`. they also support postfix syntax,
   and can be written like `1.#saturating_add(2)`. any boa compiler will need
   to implement these, as they are compiler intrinsics and don't have code
   implementations.
1. `core` - this is the language's standard libaray. the reference
   implementation is implemented in boa and interfaces directly with the kernel
   of the system it is built on. these are generic functions that any software
   may use, from embedded hardware, to high-level games. memory allocations
   should be explicit, i.e. we are explicitly passing around allocators, and
   when allocations are unnecessary, the function simply doesn't receive an
   allocator. this is compiled into a static library and is staticly linked to
   all programs unless the compiler is explicitly told not to link core.

   the core is separated into a number of subnamespaces, which implement
   functionality for common structures. for example, array lists are in their
   own namespace, which implements the init, deinit, push, etc functions. these
   can be pulled out and used in functions as shorthands:

   ```text
   const func = fn(allocator: core#Allocator) void {
     const array_list = core#array_list;

     let mut data = array_list#init(bool, allocator);
     defer data.array_list#deinit();

     for i in 0..10 {
       if core#rand(bool) {
         out.array_list#push(core#rand(bool));
       }
     }

     for i in data.view {
       core#print("value: %b", .{i});
     }
   };
   ```

1. `vendor` - this is a set of libaries that the language implementation
   includes with its installation. it is any libraries that the implementors
   decide are useful or common enough to include with the language itself. this
   means that different toolchains may include different libraries and overall
   do things a little differently, while still including a relatively similar
   development experience with common `builtin` and `core` experiences. there
   are no restrictions and no requirements for the vendor. i'm thinking the
   reference toolchain may allow for multiple vendors, so that there isn't
   really a single centralized set of libraries, different _popular_
   perspectives may be included.
1. `external` - in the event where functionality isn't included in any of the
   above sources, external modules may be imported. there will never be an
   official centalized repository of modules, rather modules may be downloaded
   from git, tarballs, or any other viable internet source. we'll need to see
   about implementing a bunch of stuff to see how these modules should be
   handled. i don't want to have to deal with the diamond import problem.

## module scoping

i really enjoy using go's module system, which utilizes the filesystem as the
structure for modules. odin does the same thing. i'll need to test a bunch to
see if it makes sense to do that with boa, since modules may need to be smaller
to account for the smaller scope of certain modules, such as `core#array_list`.
however, that is one single example, so maybe most other modules will be larger
and need to span multiple files to feel nice to use.

## struct field access

so one thing to think about is how to do struct field access. there are a few
different approaches that may work better or worse for the design so far:

1. **public only** - this is kinda like the C style of doing things. structs
   are declared and all fields are implicitly public. this will make extending
   the data extremely easy so external modules may make more customized
   functionality. however, this has implications about the public api. this
   effectively eliminates the possibility of having "implementation details";
   every part of the data side of the implementation is public api. this
   _could_ be remediated by documenting that certain fields are not part of the
   public api contract, which may offer some relief to this issue
1. **doc comments** - here, we just document that the field is private. the
   field will not show up in documentation, meaning the field is not part of
   the public api. no restrictions from the language side, just a difference in
   what shows up in documentation. need to think about if this should show up
   in text hover lsp and/or highlight in a special way in editors.
1. **soft visibility specifiers** - this would mean that i could define fields
   in my struct as private, but the enforcement of the visibility would be soft.
   effectively, using a private field doesn't throw an error in any way, however
   the field isn't included in any documentation, cementing that the field is
   not part of the public api. this may offer the most flexibility, allowing for
   external modules to use and modify implementation details, while not being
   restricted in what they can do. although it may lead to extensive usage of
   private apis, leading to often breakage. will need to see. need to think
   about if this should show up in text hover lsp and/or highlight in a special
   way in editors.
1. **hard visibility specifiers** - here is where the compiler actually
   enforces visibility. essentially, if a module outside of the module where
   the struct is defined, the compiler will throw an error saying this isn't
   allowed. the main issue here is that it will limit what external modules are
   actualy able to do with internal apis. this may or may not be an issue,
   depending on the implementation of the api. e.g. if we give enough offramps,
   this shouldn't be an issue.

kinda between soft and hard visibility specifiers. if i implement soft
visibility, it should be simple enough to implement hard visibility in the
compiler later if i feel like soft doesnt work well. similar vice versa, except
if i implement hard visibility first, removing it will not be a breaking change
in the language. probably going to go with that.
