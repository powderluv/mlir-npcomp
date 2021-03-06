//===-------------------------------------------------------*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef TORCH_OPS
#define TORCH_OPS

include "npcomp/Dialect/Torch/IR/TorchTypes.td"
include "npcomp/Dialect/Torch/IR/OpInterfaces.td"
include "mlir/IR/SymbolInterfaces.td"

class Torch_Op<string mnemonic, list<OpTrait> traits = []>
    : Op<Torch_Dialect, mnemonic, traits> {
}

// TODO: Add alias mapping from the signature and use it to implement the
// effects interface (since whether the kernel_call has side effects is
// dependent on its metadata).
def Torch_KernelCallOp : Torch_Op<"kernel_call", [
    DeclareOpInterfaceMethods<TorchKernelOpInterface>]> {
  let summary = "Calls a Torch custom kernel";
  let description = [{
    Torch kernel calls are matched by the runtime based on signature, including
    the fully qualified kernel name (i.e. "namespace::name") and the tuple of
    argument types. This op models such an invocation.
  }];

  let arguments = (ins
    StrAttr:$kernelName,
    Variadic<AnyTorchType>:$args,
    StrArrayAttr:$sigArgTypes,
    StrArrayAttr:$sigRetTypes,
    BoolAttr:$sigIsVararg,
    BoolAttr:$sigIsVarret,
    BoolAttr:$sigIsMutable
    // TODO: Add alias mapping.
  );
  let results = (outs
    Variadic<AnyTorchType>:$results
  );

  let assemblyFormat = [{
    $kernelName $args `:` functional-type($args, results) attr-dict
  }];
}

//===----------------------------------------------------------------------===//
// TorchScript `torch.nn.Module` object instantiation ops.
//===----------------------------------------------------------------------===//

def Torch_NnModuleOp : Torch_Op<"nn_module", [
    DeclareOpInterfaceMethods<SymbolUserOpInterface>,
    SingleBlockImplicitTerminator<"::mlir::NPCOMP::Torch::NnModuleTerminatorOp">]> {
  let summary = "Constructs a torch.nn.Module";
  let description = [{
    This op is used to represent a torch.nn.Module when importing a
    graph of Python objects.

    This op returns a new torch.nn.Module as an SSA value, with a set of
    declaratively specified properties.

    Example:

    ```mlir
    %2 = torch.nn_module {
      torch.slot "b", %bool_true : !basicpy.BoolType
      torch.slot "i", %num3_i64 : i64
      torch.slot "f", %num : f64
      torch.slot "t", %0 : !numpy.ndarray<*:!numpy.any_dtype>
      torch.slot "submodule", %1 : !torch.nn.Module
    } : !torch.nn.Module<"my_class_name">
    ```

    This op is tightly coupled to the `torch.class_type` op named in the
    `!torch.nn.Module<"my_class_name">` type. Each slot must match precisely
    with the corresponding `torch.attr` in the `torch.class_type`.
    See the documentation for `torch.class_type` for information.
  }];

  let arguments = (ins);
  let results = (outs Torch_NnModuleType:$result);
  let regions = (region SizedRegion<1>:$region);
  let verifier = "return ::verify(*this);";

  let assemblyFormat = "$region attr-dict `:` type($result)";

  let extraClassDeclaration = [{
    StringRef getClassName() { return getType().getClassName(); }
  }];
}

def Torch_NnModuleTerminatorOp : Torch_Op<"nn_module_terminator", [Terminator,
    HasParent<"::mlir::NPCOMP::Torch::NnModuleOp">]> {
  let summary = "Implicit terminator for torch.nn_module";

  let arguments = (ins);
  let results = (outs);

  let assemblyFormat = "attr-dict";
}

def Torch_SlotOp : Torch_Op<"slot", [
    HasParent<"::mlir::NPCOMP::Torch::NnModuleOp">]> {
  let summary = "Define the value of a slot of a torch.nn.Module";
  let description = [{
    This op specifies that the initial value of the slot `name` of the
    parent torch.nn_module should be `value`, which is allowed to be an
    arbitrary Torch-compatible SSA value, including other !torch.nn.Module's.
  }];

  let arguments = (ins StrAttr:$name, AnyTorchType:$value);
  let results = (outs);

  let assemblyFormat = [{
    $name `,` $value attr-dict `:` type($value)
  }];
}

//===----------------------------------------------------------------------===//
// Modeling of TorchScript class types
//===----------------------------------------------------------------------===//

def Torch_ClassTypeOp : Torch_Op<"class_type", [
    Symbol,
    SingleBlockImplicitTerminator<"::mlir::NPCOMP::Torch::ClassTypeTerminatorOp">]> {
  let summary = "Constructs a torch.ClassType";
  let description = [{
    Declares a class type. Class types are the types used to describe
    TorchScript `torch.nn.Module`'s. The terminology "class type" is for
    consistency with TorchScript (a better name in our context might be
    "nn module subtype"). The `syn_name` of this op is the same string
    as in the `!torch.nn.Module<"...">` type.

    Example:

    ```mlir
    // A simple empty torch.class_type, with corresponding torch.nn_module.
    torch.class_type @empty {}
    %submodule = torch.nn_module {} : !torch.nn.Module<"empty">

    // A class type with many members.
    torch.class_type @test {
      torch.attr "b" : !basicpy.BoolType
      torch.attr "i" : i64
      torch.attr "f" : f64
      torch.attr "t" : !numpy.ndarray<*:!numpy.any_dtype>
      torch.attr "submodule" : !torch.nn.Module<"empty">
      torch.method "method", @f
    }
    torch.nn_module {
      // These must match the order and names in the `torch.class_type`.
      torch.slot "b", %bool_true : !basicpy.BoolType
      torch.slot "i", %num3_i64 : i64
      torch.slot "f", %num : f64
      torch.slot "t", %array : !numpy.ndarray<*:!numpy.any_dtype>
      torch.slot "submodule", %submodule : !torch.nn.Module<"empty">
    } : !torch.nn.Module<"test">
    ```
  }];

  let arguments = (ins SymbolNameAttr:$sym_name);
  let results = (outs);
  let regions = (region SizedRegion<1>:$region);
  let verifier = "return ::verify(*this);";

  let assemblyFormat = "$sym_name $region attr-dict";
}

def Torch_ClassTypeTerminatorOp : Torch_Op<"class_type_terminator", [Terminator,
    HasParent<"::mlir::NPCOMP::Torch::ClassTypeOp">]> {
  let summary = "Implicit terminator for torch.class_type";

  let arguments = (ins);
  let results = (outs);

  let assemblyFormat = "attr-dict";
}

def Torch_MethodOp : Torch_Op<"method", [
    HasParent<"::mlir::NPCOMP::Torch::ClassTypeOp">,
    DeclareOpInterfaceMethods<SymbolUserOpInterface>
  ]> {
  let summary = "Declare a method of a torch.class_type";
  let description = [{
    This op declaratively specifies that the parent torch.class_type has a
    method `name` which calls `function`. `function` is an unbound function.
    That is, it explicitly takes the torch.nn.Module as a parameter (no implicit
    "self" object).
  }];

  let arguments = (ins StrAttr:$name, FlatSymbolRefAttr:$function);
  let results = (outs);

  let assemblyFormat = [{
    $name `,` $function attr-dict
  }];
}

def Torch_AttrOp : Torch_Op<"attr", [
    HasParent<"::mlir::NPCOMP::Torch::ClassTypeOp">
  ]> {
  let summary = "Declare an attribute of a torch.class_type";
  let description = [{
    This op declaratively specifies that torch.nn.Module's of the parent
    torch.class_type must have an attribute `name` of type `type`.
  }];

  let arguments = (ins StrAttr:$name, TypeAttr:$type);
  let results = (outs);

  let assemblyFormat = [{
    $name `:` $type attr-dict
  }];
}

//===----------------------------------------------------------------------===//
// Global slot ops
//===----------------------------------------------------------------------===//
// TODO: Should these be in a separate dialect?
// At this point, they are fairly specific to torch types, but their get/set
// semantics follow Python.
//===----------------------------------------------------------------------===//

def Torch_GlobalSlotOp : Torch_Op<"global_slot", [
    Symbol,
    IsolatedFromAbove,
  ]> {
  let summary = "A slot with global storage";
  let description = [{
    Represents a slot with global storage. The slot semantics are the same
    as Python's: getting or setting a slot is done by object identity.
  }];

  let arguments = (ins SymbolNameAttr:$sym_name, TypeAttr:$typeBound);
  let results = (outs);


  let assemblyFormat = [{
    $sym_name attr-dict `:` $typeBound
  }];

  let extraClassDeclaration = [{
    // The name of the function, which, for semantic correctness, must be called
    // exactly once and this call must be done before any other calls into
    // the module.
    // TODO: Avoid load-bearing names.
    // We could replace this with an op that marks the function as initializer.
    static constexpr StringRef getGlobalSlotInitializerFuncName() {
      return "__torch_global_slot_initializer";
    }
  }];
}

def Torch_GlobalSlotGetOp : Torch_Op<"global_slot.get", []> {
  let summary = "Get the value stored in a torch.global_slot";

  let arguments = (ins
    FlatSymbolRefAttr:$slot
  );
  let results = (outs AnyTorchType:$result);

  let assemblyFormat = [{
    $slot attr-dict `:` type($result)
  }];
}

def Torch_GlobalSlotSetOp : Torch_Op<"global_slot.set", []> {
  let summary = "Set the value stored in a torch.global_slot";

  let arguments = (ins
    FlatSymbolRefAttr:$slot,
    AnyTorchType:$value
  );
  let results = (outs);

  let assemblyFormat = [{
    $slot `=` $value attr-dict `:` type($value)
  }];
}

//===----------------------------------------------------------------------===//
// TorchScript `prim::` ops.
//===----------------------------------------------------------------------===//

def Torch_PrimGetAttrOp : Torch_Op<"prim.GetAttr", []> {
  let summary = "TorchScript prim::GetAttr op";

  let arguments = (ins StrAttr:$name, Torch_NnModuleType:$receiver);
  let results = (outs AnyTorchType:$result);

  let assemblyFormat = [{
    $receiver `[` $name `]` attr-dict `:` type($receiver) `->` type($result)
  }];
}

def Torch_PrimSetAttrOp : Torch_Op<"prim.SetAttr", []> {
  let summary = "TorchScript prim::SetAttr op";

  let arguments = (ins
    StrAttr:$name,
    Torch_NnModuleType:$receiver,
    AnyTorchType:$value
  );
  let results = (outs);

  let assemblyFormat = [{
    $receiver `[` $name `]` `=` $value attr-dict `:` type($receiver) `,` type($value)
  }];
}

def Torch_PrimCallMethodOp : Torch_Op<"prim.CallMethod", []> {
  let summary = "TorchScript prim::CallMethod op";

  let arguments = (ins
    StrAttr:$name,
    Torch_NnModuleType:$receiver,
    Variadic<AnyTorchType>:$operands
  );
  let results = (outs AnyTorchType:$result);

  let assemblyFormat = [{
    $receiver `[` $name `]` `(` $operands `)` attr-dict `:` type($receiver) `,` functional-type($operands, $result)
  }];
}

def Torch_PrintOp : Torch_Op<"prim.Print", []> {
  let summary = "TorchScript prim::Print op";

  let arguments = (ins Variadic<AnyTorchType>:$operands);
  let results = (outs);

  let assemblyFormat = [{
    `(` $operands `)` attr-dict `:` type($operands)
  }];
}

#endif // TORCH_OPS
