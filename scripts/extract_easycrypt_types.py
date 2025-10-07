#!/usr/bin/env python3
"""
EasyCrypt Type Information Extractor

This script systematically extracts type definitions, constructors, and API functions
from EasyCrypt source code to help with AST serialization and type-safe development.

Usage:
    python3 extract_easycrypt_types.py [--output-dir OUTPUT_DIR] [--easycrypt-path PATH]
"""

import os
import re
import json
import argparse
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass, asdict

@dataclass
class TypeInfo:
    name: str
    module: str
    kind: str  # 'type', 'variant', 'record', 'alias'
    constructors: List[str]
    fields: List[Tuple[str, str]]  # (field_name, field_type)
    api_functions: List[str]  # functions that work with this type
    file_path: str
    line_number: int

@dataclass
class ModuleInfo:
    name: str
    file_path: str
    types: List[TypeInfo]
    functions: List[str]

class EasyCryptTypeExtractor:
    def __init__(self, easycrypt_path: str):
        self.easycrypt_path = Path(easycrypt_path)
        self.src_path = self.easycrypt_path / "src"
        self.extracted_data: Dict[str, ModuleInfo] = {}
        
    def extract_all(self) -> Dict[str, Any]:
        """Extract all type information from EasyCrypt source."""
        print(f"🔍 Extracting types from {self.src_path}")
        
        # Key modules for AST serialization
        target_modules = [
            "ecAst.ml", "ecTypes.ml", "ecCoreFol.ml", 
            "ecBaseLogic.ml", "ecEnv.ml", "ecUid.ml",
            "ecIdent.ml", "ecPath.ml", "ecCoreGoal.ml"
        ]
        
        for module_file in target_modules:
            self.extract_module(module_file)
            
        return {
            "modules": {name: asdict(module) for name, module in self.extracted_data.items()},
            "summary": self._generate_summary()
        }
    
    def extract_module(self, module_file: str):
        """Extract type information from a specific module."""
        file_path = self.src_path / module_file
        if not file_path.exists():
            print(f"⚠️  Module not found: {module_file}")
            return
            
        print(f"📄 Processing {module_file}")
        
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
            
        module_name = module_file.replace('.ml', '').replace('.mli', '')
        types = []
        functions = []
        
        # Extract type definitions
        type_patterns = [
            # Type aliases: type name = existing_type
            (r'type\s+(\w+)\s*=\s*(\w+(?:\.\w+)*)', 'alias'),
            # Records: type name = { field1: type1; field2: type2; }
            (r'type\s+(\w+)\s*=\s*\{([^}]+)\}', 'record'),
            # Variants: type name = | Constructor1 of type1 | Constructor2 of type2
            (r'type\s+(\w+)\s*=\s*([^=]+?)(?=\n\s*(?:type|val|let|module|\Z))', 'variant'),
        ]
        
        for pattern, kind in type_patterns:
            for match in re.finditer(pattern, content, re.MULTILINE | re.DOTALL):
                type_name = match.group(1)
                type_body = match.group(2) if len(match.groups()) > 1 else ""
                
                constructors = []
                fields = []
                
                if kind == 'record':
                    # Parse record fields
                    field_matches = re.finditer(r'(\w+)\s*:\s*([^;]+)', type_body)
                    for field_match in field_matches:
                        field_name = field_match.group(1)
                        field_type = field_match.group(2).strip()
                        fields.append((field_name, field_type))
                        
                elif kind == 'variant':
                    # Parse variant constructors
                    constructor_matches = re.finditer(r'\|\s*(\w+)(?:\s+of\s+([^|]+))?', type_body)
                    for const_match in constructor_matches:
                        constructor = const_match.group(1)
                        constructor_type = const_match.group(2).strip() if const_match.group(2) else ""
                        constructors.append(constructor)
                        if constructor_type:
                            fields.append((f"{constructor}_arg", constructor_type))
                
                # Find API functions for this type
                api_functions = self._find_api_functions(content, type_name)
                
                type_info = TypeInfo(
                    name=type_name,
                    module=module_name,
                    kind=kind,
                    constructors=constructors,
                    fields=fields,
                    api_functions=api_functions,
                    file_path=str(file_path),
                    line_number=content[:match.start()].count('\n') + 1
                )
                types.append(type_info)
        
        # Extract function signatures
        function_pattern = r'val\s+(\w+)\s*:\s*([^=]+?)(?=\n\s*(?:val|type|let|module|\Z))'
        for match in re.finditer(function_pattern, content, re.MULTILINE | re.DOTALL):
            func_name = match.group(1)
            func_sig = match.group(2).strip()
            functions.append(f"{func_name}: {func_sig}")
        
        self.extracted_data[module_name] = ModuleInfo(
            name=module_name,
            file_path=str(file_path),
            types=types,
            functions=functions
        )
    
    def _find_api_functions(self, content: str, type_name: str) -> List[str]:
        """Find functions that work with a specific type."""
        functions = []
        
        # Look for functions that take or return this type
        patterns = [
            rf'val\s+(\w+)\s*:\s*[^=]*{re.escape(type_name)}[^=]*',
            rf'val\s+(\w+)\s*:\s*[^=]*->\s*[^=]*{re.escape(type_name)}[^=]*',
        ]
        
        for pattern in patterns:
            for match in re.finditer(pattern, content, re.MULTILINE):
                func_name = match.group(1)
                if func_name not in functions:
                    functions.append(func_name)
        
        return functions
    
    def _generate_summary(self) -> Dict[str, Any]:
        """Generate a summary of extracted information."""
        total_types = sum(len(module.types) for module in self.extracted_data.values())
        total_functions = sum(len(module.functions) for module in self.extracted_data.values())
        
        type_kinds = {}
        for module in self.extracted_data.values():
            for type_info in module.types:
                kind = type_info.kind
                type_kinds[kind] = type_kinds.get(kind, 0) + 1
        
        return {
            "total_modules": len(self.extracted_data),
            "total_types": total_types,
            "total_functions": total_functions,
            "type_kinds": type_kinds,
            "modules": list(self.extracted_data.keys())
        }
    
    def generate_ocaml_helpers(self) -> str:
        """Generate OCaml helper code for type access."""
        ocaml_code = []
        ocaml_code.append("(* Auto-generated EasyCrypt type access helpers *)")
        ocaml_code.append("(* Generated by extract_easycrypt_types.py *)")
        ocaml_code.append("")
        
        for module_name, module_info in self.extracted_data.items():
            ocaml_code.append(f"(* {module_name} module *)")
            
            for type_info in module_info.types:
                if type_info.kind == 'record':
                    ocaml_code.append(f"(* {type_info.name} record fields: *)")
                    for field_name, field_type in type_info.fields:
                        ocaml_code.append(f"(*   {field_name}: {field_type} *)")
                    ocaml_code.append("")
                elif type_info.kind == 'variant':
                    ocaml_code.append(f"(* {type_info.name} variant constructors: *)")
                    for constructor in type_info.constructors:
                        ocaml_code.append(f"(*   {constructor} *)")
                    ocaml_code.append("")
            
            # Add API functions
            if module_info.functions:
                ocaml_code.append(f"(* {module_name} API functions: *)")
                for func in module_info.functions[:10]:  # Limit to first 10
                    ocaml_code.append(f"(*   {func} *)")
                if len(module_info.functions) > 10:
                    ocaml_code.append(f"(*   ... and {len(module_info.functions) - 10} more *)")
                ocaml_code.append("")
        
        return "\n".join(ocaml_code)
    
    def generate_typescript_interfaces(self) -> str:
        """Generate TypeScript interfaces for the extracted types."""
        ts_code = []
        ts_code.append("// Auto-generated TypeScript interfaces for EasyCrypt types")
        ts_code.append("// Generated by extract_easycrypt_types.py")
        ts_code.append("")
        
        for module_name, module_info in self.extracted_data.items():
            ts_code.append(f"// {module_name} module")
            
            for type_info in module_info.types:
                if type_info.kind == 'record':
                    ts_code.append(f"interface {type_info.name} {{")
                    for field_name, field_type in type_info.fields:
                        ts_type = self._ocaml_to_typescript_type(field_type)
                        ts_code.append(f"  {field_name}: {ts_type};")
                    ts_code.append("}")
                    ts_code.append("")
                elif type_info.kind == 'variant':
                    ts_code.append(f"type {type_info.name} =")
                    for i, constructor in enumerate(type_info.constructors):
                        prefix = "  | " if i > 0 else "  "
                        ts_code.append(f"{prefix}'{constructor}'")
                    ts_code.append("")
        
        return "\n".join(ts_code)
    
    def _ocaml_to_typescript_type(self, ocaml_type: str) -> str:
        """Convert OCaml type to TypeScript type."""
        type_mapping = {
            'int': 'number',
            'string': 'string',
            'bool': 'boolean',
            'unit': 'void',
            'list': 'Array',
            'option': 'T | null',
        }
        
        # Simple mapping for now
        for ocaml, ts in type_mapping.items():
            if ocaml in ocaml_type:
                return ts
        
        return 'any'  # Fallback

def main():
    parser = argparse.ArgumentParser(description='Extract EasyCrypt type information')
    parser.add_argument('--easycrypt-path', default='/home/marcilunga/dev/easycrypt',
                       help='Path to EasyCrypt source directory')
    parser.add_argument('--output-dir', default='extracted_types',
                       help='Output directory for generated files')
    parser.add_argument('--format', choices=['json', 'ocaml', 'typescript', 'all'], 
                       default='all', help='Output format')
    
    args = parser.parse_args()
    
    # Create output directory
    output_dir = Path(args.output_dir)
    output_dir.mkdir(exist_ok=True)
    
    # Extract types
    extractor = EasyCryptTypeExtractor(args.easycrypt_path)
    data = extractor.extract_all()
    
    # Generate outputs
    if args.format in ['json', 'all']:
        json_file = output_dir / 'easycrypt_types.json'
        with open(json_file, 'w') as f:
            json.dump(data, f, indent=2)
        print(f"✅ Generated {json_file}")
    
    if args.format in ['ocaml', 'all']:
        ocaml_file = output_dir / 'easycrypt_types.ml'
        with open(ocaml_file, 'w') as f:
            f.write(extractor.generate_ocaml_helpers())
        print(f"✅ Generated {ocaml_file}")
    
    if args.format in ['typescript', 'all']:
        ts_file = output_dir / 'easycrypt_types.ts'
        with open(ts_file, 'w') as f:
            f.write(extractor.generate_typescript_interfaces())
        print(f"✅ Generated {ts_file}")
    
    # Print summary
    summary = data['summary']
    print(f"\n📊 Extraction Summary:")
    print(f"   Modules: {summary['total_modules']}")
    print(f"   Types: {summary['total_types']}")
    print(f"   Functions: {summary['total_functions']}")
    print(f"   Type kinds: {summary['type_kinds']}")

if __name__ == '__main__':
    main()
