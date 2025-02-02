# notes

here are some general notes that i have about the language, language design,
standard library, etc.

i feel like a big thing driving the design of the language is decoupling
functionality and data, but still allowing for a relationship between data and
functionality.

## language northstars

the main hypothesis of the language is that through language simplicity and
consistency, the cognitive load required to maintain context of the language
will be substantially decreased, allowing more mental capacity to be used on the
actual problem at hand.

for example, rust's type system is very difficult. even by just understanding
the lifetime system and borrow checker, one still isnt even close to mastering
the language. there are still concepts like pinning, arcing, etc. i DO NOT want
that.

the northstars are:

1. **simplicity** - only the features are required should be implemented. the
   language itself should only implement what is required to generate the
   machine code. the standard library should only implement what is required to
   perform basic operations with the language. vendor libraries can implement
   whatever lol
1. **consistency** - the features of the language should be consistent. there
   shouldn't be any obvious or niche footguns or exceptions to the rules of the
   language.

the main idea of this approach is to keep control in the hands of the users of
the language. instead of building features into the language or the compiler,
features should be deferred to userland as much as possible. for example, struct
packing _could_ be a compiler feature, but it would be **much** more powerful to
have it implemented in userland as that would enable users to build their own
packing algorithms or even build out other struct re-ordering systems.

by doing this, the language and the compiler should never get in the way of the
user. the user should always have the option of just writing code to do what
they want to do. this will be of additional benefit to the compiler engineers
and language designers, because it will force the language to be simple and, as a
consequence, the compiler as well.

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

alternatively, the `#` symbol could designate postfix, and `.` could be access.
so a code example for this could look like the following:

```text
data
  #namespace1.function1(data.field)
  #.builtin()
  #namespace2.function2()
```

the equivalent other syntax would be the following:

```text
data
  .namespace1#function1(data#field)
  .#builtin()
  .namespace2#function2()
```

i think i like this one ^ more. a big thing is that having a universal postfix
and access syntax will make lexing and parsing WAY easier. and i think the `.`
as postfix and `#` as access looks better than vice versa. the field access is
just a little caveat of that, but i think it looks fine. keeping these syntaxes
simple and consistent will make the compiler and tooling way easier to build and
work with, and should make the language easier to learn.

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

## multi tasking

this is a doosy so strap in. i really like the threading model of go, and would
like to include a system like that in boa. however, the whole idea is to not
take control away from the user of the language. from a standard library
perspective, system threads should be exposed. anyone wanting to use system
threads directly should have clear and easy access to do so.

however, one of the reference vendor libraries should be a fibers module. this
should give a coroutine experience, where each separate task is just a function.
these can be configured to use cooperative or preemptive scheduling or a mixture
of the two to offer different approaches to the threading. of course, as with
everything, the defaults should work for 95% of projects, but give escape
hatches where users will want them.

each fiber gets its own stack. this is the main overhead of the whole system. if
we allocate a ~2k stack for each fiber, that will result in ~2GB being used as
stack space for 1 million fibers. tbh, not terrible but also no great. to
partially remedy this, we can dynamically expand, use pools to allocate stacks,
and use memory-mapped stacks to help ease up on memory usage. this is the
primary drawback of using fibers, but the benefits severely outweigh the
problems.

with a fiber-based approach, we get some nice benefits that align with the
philosophy of the language. the implementation should be relatively easy. the
primary start mechanism of the fiber system should be plain function calls. this
should keep the stack clean and easy to debug. it won't require any special
implementation on the compiler's end or any crazy stuff in the language runtime.
the entire implementation should exist in userland, implemented in plain boa, as
a library.

fibers should essentially be implemented as green threads. the fiber runtime
should be started as a regular function call, which should spin up a number of
system threads (probably the number of logical cores the cpu has), then run a
scheduler that is work stealing and fair.

we should also be able to maintain stack traces to an extent. at the callsite of
a fiber spawn, we should be able to snatch the current stacktrace and pin it to
the metadata of the fiber. this should help a great deal with debugging, as
stack traces will be preserved, so call traces will remain clear and easy to
locate.

preemption is another feature that should be pretty nice. cooperative
multitasking is great when each task is fair about the time it spends, but it is
waaaaayyyyy easier to write code that isnt fair, than code that is. preemption
is the primary way to get around this, and what i would expect many people to
prefer instead of going about making sure all their code is fair. goroutines use
userland preemption, so how hard could it be xD

it is important to me that fibers do not create function coloring. the great
thing about goroutines is that everything is just a function. no defining it as
async or whatever. this is extremely important for refactoring sake and also
simplicity from the user's perspective.

blocking os tasks like file reading should also yield if possible. pretty much
anything that may block the current thread should yield i think. we'll need to
check if this can be done in a very efficient way. i dont want to be doing a
bunch of checks on every syscall for if this current context is in a fiber, then
trying to yield and all that. like if we can implement preemption through
interrupts or something like that, try to do the interrupt. idk, but it should
be pretty efficient while still allowing extensibility.

another point is that maybe this would be a good opportunity to be able to do
metaprogramming so that i can spawn a fiber with similar syntax to a goroutine.
like if i could spawn a fiber like `my_func(data1, data2).fibers#spawn(rt)` and
that would package the call into a closure, capture the current stack, etc. and
perform the underlying call with all that data.

overall, the implementation should be relatively simple, live entirely in
userland, and offer many points of configuration and tuning. it should also be
fairly lightweight and scalable.

## metaprogramming

i really love zig's metaprogramming. all a single language, no additional
context, and the ability to build some super incredible apis. i am 100% about
implementing that type of metaprogramming and lazy type checking.

the type of metaprogramming i am still iffy about is the full fat you can
implement a dsl in the language type of metaprogramming. something like you can
do i jai or i think ruby. the real big thing about that is that it will decrease
both northstars. the language will become less consistent, as anyone can write
any syntax they want - if they want to do access with a period, they could write
that. additionally, it will decrease the simplicity of the language by enabling
more complexity through custom dsls.

i still need to learn a lot more about all that metaprogramming, but right now
im still on the fence on full fat metaprogramming. some of the features that i
want to implement could benefit from all that, but also maybe there are other
approaches that im not thinking of that could give me the same sort of
functionality. additionally, maybe there are ways that i could lock down the
metaprogramming to make sure it doesnt compromise on simplicity and consistency?

### jan 31, 2025

coming back to this, im wondering if function calls should be the only form of
full metaprogramming? for example, maybe i could write this for spawing a fiber:

```text
my_fiber(data).fibers#spawn(rt);
```

and that `fibers#spawn` function would be a function, like any other:

```text
const spawn = fn(e: expr, rt: Runtime) expr {
  // ...
};
```

where `expr` is a special type, like the `type` datatype, that represents an
expression in the code. i feel like this would be kinda like jai
metaprogramming, but ill need to read more about that. the idea is that i can
write some code, and whenever a function deals with `expr`, it must be run at
compile time. the `expr` is a structure provided directly by the compiler,
representing the expression it is being called with. i am unsure if this should
be a token stream or some other structure, still working through that.

but, this would allow effectively rewriting code like macros, if i go with a
token stream. if i go with something more structured, it could provide even more
data to the function, which could generate more complex code out the back end. i
dont know, need to think more about all this stuff.

#### later

i'm coming more around to the idea of having a function that can take in an
expression and return an expression. that will require the notion of having
`const` functions, but that's fine. `expr` can only exist on a const function.
it should also work fine for postfix syntax, since the postfix notation will
just generate function call expressions where the first parameter is the
preceding expression.

i think also allowing anything as a parameter and returning an expression should
be pretty good. that should allow for more interesting dsls where the logic is
still explicitly a function call.

### Feb 1, 2025

okay i should probably have the option to pass around plain tokens in addition
to the expr and the string inputs. ill need to create some sort of pattern to
enable this properly and fully, but i'm looking at something like this:

```text
const my_dsl = dsl()
  .#meta(
    <Widget with={properties}>
      <Text>my input!</Text>
    </Widget>
  );
```

i dont know how much i like that, but that will enable custom parsing of inputs
to enable markup expansion into proper code, like react :3. but now i must think
of if i want that. ui implemented in markup is objectively ideal. but is this
the right way to go about it? would it be better to have some sort of special
string stuff going on? but then again i would like to be able to have kinda good
error messages and parsing tokens directly from the lexer would be best for
that.

#### later - maybe no need for custom meta function?

so i think, to be honest, it could use a phased parsing system, where we just
make sure we match on openers and closers, like matching `(` and `)`. then we
can parse out the top level, build a symbol table with functions, then start
parsing out the smaller instructions, then we would know which function calls
need a plain set of tokens, or actual values or whatever. that of course means
that there are specific tokens that MUST match. so for example, we couldnt do
that with `<` and `>` since those can be used for numeric comparisons.

this means we could do something like this instead:

```text
const dsl = fn(tokens: []const #Token) #Expr {
  // ...
};

const my_dsl = dsl(
  <Widget with={properties}>
    <Text>my input!</Text>
  </Widget>
);
```

## type inference

so one thing i am realizing is type inference is going to need to be a thing.
since functions can't have associated functions, we need to be able to infer
types from type parameters. as an example:

```text
// in module array_list

const ArrayList = fn(T: type) type {
  return struct {
    .items = []T,
  };
};

const append = fn(self: *ArrayList(infer T), item: T) void {
  // ...
};
```

i don't think this should be too hard. the type coming into that function must
always be concrete. additionally, a struct constructed manually will not be
equivalent to the struct created in the `ArrayList` function. with this, the
type system should be able to infer that type for usage within the function
definition as well as in the function implementation.

we also shouldnt need to worry about type constraint. again, the type passed
into a function _must_ be a concrete type. in other words, it will never be an
interface type, meaning the type cannot be constrained in any way.

this doesnt feel like a _great_ feature, but it will make building apis wayyyy
nicer since that type is already known by the compiler. it doesnt make sense to
make it yet another type parameter when it can be inferred by the compiler.
while escape hatches are kinda annoying, this is the only one i've come across
in this design, so i feel pretty fine about it.

### Feb 1, 2025 - computed modules

i have come back around on this. adding infer syntax is just plain wrong.
metaprogrammed modules are the way to go. if im going to yank out the module for
easier access anyway, i might as well compute the module at that point too.

```text
const array_list = fn(T: type) module {
  return module {
    pub const Type = struct {
      .items = []T,
    };

    pub const append = fn(self: *Type, item: T) void {
      // ...
    };
  };
};
```

will need to figure out more of that syntax, but this is the way to implement
it. i genuinely have no idea what i was thinking...

## MODULES

okay ngl, this is something i have been neglecting thinking about. the issue
right now is that we should be using directory-level modules. BUTTT if we want
everything super declarative, i.e. imports like `const core = #import("core");`,
we need to play with visibilities. this is because imports _should_ be scoped to
the file. that is how it should be. HOWEVER if every file imports the same
library in a module, there are obviously going to be name collisions. we cant
have one import for the entire module cuz it will be hard to track which file
has it.

okay so all these things together mean that we need to play with visibility
within the module. that way, each file can import the module like above, but it
wont collide across the entire module. so that means we need at least 3 levels
of visibility:

1. private - only visible to the current file
1. module - only visible to the current module
1. public - visible to outside the current module

the only thing to think about is going to be it i want that. go gets around this
by having special syntax for importing, which is scoped to the current file.
maybe want that, but then maybe that means rethinking how everything is done at
the top level?

### Feb 2, 2025 - local visibility

for this, i think a new local variable type should be done. so that means we
have:

- **`const`** - constant variable. this must be evaluable at compile time
- **`let`** - variable. this is runtime evaluated and can optionally be mutable
- **`local`** - local constant variable. same as `const` but can only be scoped
  to the current file

this fixes the import issue, where imports _need_ to be file-scoped. just add a
new variable type and we're done. this has the additional benefit of allowing
users to write file-local variables if they need to, for example, for submodule
extraction.
