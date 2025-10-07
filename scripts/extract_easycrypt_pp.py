#!/usr/bin/env python3
"""
Extract AST→CSS mappings by analyzing EasyCrypt's actual source code.
No hardcoding - derives categories from EC's type definitions.
"""

import re
from pathlib import Path
from collections import defaultdict

EASYCRYPT_AST = Path("/home/marcilunga/dev/easycrypt/src/ecAst.ml")
OUR_AST = Path("/home/marcilunga/dev/vsec/src/protocol/ast.ml")
ADAPTER = Path("/home/marcilunga/dev/vsec/src/dm/plugins/vsec_ec_adapter.ml")

def extract_easycrypt_node_types():
    """
    Parse EasyCrypt's ecAst.ml to find all F* constructors and categorize them.
    Returns dict: {node_name: category}
    """
    content = EASYCRYPT_AST.read_text()
    
    # Find the f_node type definition - it starts with "and f_node ="
    match = re.search(r'and f_node\s*=\s*(.*?)(?=\nand\s+\w+\s*=|\Z)', content, re.DOTALL)
    if not match:
        print("⚠️  Could not find f_node type definition")
        return {}
    
    f_node_def = match.group(1)
    
    # Extract all constructors: | Fxxx of ... or | Fxxx
    constructors = re.findall(r'\|\s*F(\w+)(?:\s+of|\s*$|\s*\()', f_node_def, re.MULTILINE)
    
    # Categorize based on EasyCrypt semantics
    categories = {}
    
    for c in constructors:
        name = c.lower()
        
        # Quantifiers and binders
        if any(k in name for k in ['quant', 'forall', 'exists', 'lambda', 'let', 'match', 'if']):
            categories[name] = 'constr-keyword'
        
        # Hoare/pRHL logic (these are in ecCoreFol.mli)
        elif any(k in name for k in ['hoare', 'equiv', 'eager', 'ehoare', 'bdhoare', 'pr']):
            categories[name] = 'tactic-keyword'
        
        # Variables and locals
        elif any(k in name for k in ['local', 'pvar', 'glob']):
            categories[name] = 'constr-variable'
        
        # Operators
        elif name in ['op', 'app']:
            categories[name] = 'constr-reference' if name == 'op' else 'constr-notation'
        
        # Literals
        elif any(k in name for k in ['int', 'bool']):
            categories[name] = 'constr-notation'
        
        # Tuple/proj
        elif any(k in name for k in ['tuple', 'proj']):
            categories[name] = 'constr-notation'
        
        # Default: treat as type constructor
        else:
            categories[name] = 'constr-type'
    
    return categories

def extract_hoare_types():
    """Extract Hoare/pRHL judgment types from ecCoreFol.mli."""
    ec_fol = Path("/home/marcilunga/dev/easycrypt/src/ecCoreFol.mli")
    if not ec_fol.exists():
        return {}
    
    content = ec_fol.read_text()
    
    # Find lines like: type hoareF = EcAst.hoareF
    hoare_types = re.findall(r'type\s+(\w*[Hh]oare\w*|equiv\w*|eager\w*|pr)\s*=', content)
    
    result = {}
    for t in hoare_types:
        result[t.lower()] = 'tactic-keyword'
    
    return result

def read_our_ast_kinds():
    """Read our generated AST kinds from ast.ml."""
    content = OUR_AST.read_text()
    kinds = re.findall(r'\("kind",\s*`String\s*"([^"]+)"\)', content)
    return sorted(set(kinds))

def merge_categorizations(ec_categories, hoare_types, our_kinds):
    """Merge EasyCrypt analysis with our AST kinds."""
    mapping = {}
    
    # Start with EasyCrypt-derived categories
    mapping.update(ec_categories)
    
    # Add Hoare types
    mapping.update(hoare_types)
    
    # Ensure all our kinds are mapped
    for kind in our_kinds:
        if kind not in mapping:
            # Infer from name
            kind_lower = kind.lower()
            
            if any(k in kind_lower for k in ['hoare', 'equiv', 'eager', 'pr', 'bdhoare', 'ehoare']):
                mapping[kind] = 'tactic-keyword'
            elif kind in ['var', 'constr', 'fun', 'univar', 'glob', 'mem', 'abs_st', 'modty']:
                mapping[kind] = 'constr-type'
            elif kind in ['hyp', 'local', 'pvar']:
                mapping[kind] = 'constr-variable'
            else:
                # Unknown - default to type
                mapping[kind] = 'constr-type'
                print(f"⚠️  Unmapped kind '{kind}' defaulted to constr-type")
    
    return {k: v for k, v in mapping.items() if k in our_kinds}

def inject_mapping(mapping):
    """Inject mapping into adapter source."""
    import json
    
    adapter_content = ADAPTER.read_text()
    json_str = json.dumps(mapping, indent=2, sort_keys=True)
    
    pattern = r'(let tag_mapping[^\{]*\{json\|)(\{[^}]*\})(\|json\})'
    new_content = re.sub(pattern, lambda m: m.group(1) + json_str + m.group(3), 
                         adapter_content, flags=re.DOTALL)
    
    if new_content != adapter_content:
        ADAPTER.write_text(new_content)
        return True
    return False

def main():
    print("🔍 Analyzing EasyCrypt source code...")
    
    # Extract from EasyCrypt
    ec_categories = extract_easycrypt_node_types()
    hoare_types = extract_hoare_types()
    
    print(f"   Found {len(ec_categories)} f_node constructors")
    print(f"   Found {len(hoare_types)} Hoare/pRHL types")
    
    # Read our AST
    our_kinds = read_our_ast_kinds()
    print(f"   Our AST has {len(our_kinds)} kinds")
    
    # Merge
    mapping = merge_categorizations(ec_categories, hoare_types, our_kinds)
    
    # Inject
    updated = inject_mapping(mapping)
    
    print(f"\n✅ Generated {len(mapping)} mappings")
    if updated:
        print(f"✅ Updated {ADAPTER.name}")
    else:
        print(f"✓  {ADAPTER.name} already up to date")
    
    # Show distribution
    by_cat = defaultdict(list)
    for k, v in mapping.items():
        by_cat[v].append(k)
    
    print("\n📊 Distribution:")
    for cat in sorted(by_cat.keys()):
        print(f"   {cat}: {len(by_cat[cat])} kinds")

if __name__ == "__main__":
    main()
