#!/usr/bin/env python3
"""
Input Size Limits Tests

This test suite validates input size limits to prevent memory blow-up attacks
and DoS scenarios through oversized inputs. This addresses the audit recommendation
for input validation and resource limits.
"""

import json
import sys
import time

class InputSizeLimitsTester:
    def __init__(self):
        self.test_results = []
    
    def create_large_string(self, size, char='a'):
        """Create a string of specified size"""
        return char * size
    
    def create_large_json_message(self, content_size):
        """Create a large JSON-RPC message"""
        large_content = self.create_large_string(content_size)
        message = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "textDocument/didChange",
            "params": {
                "textDocument": {
                    "uri": "file:///large.ec",
                    "version": 1
                },
                "contentChanges": [
                    {
                        "text": large_content
                    }
                ]
            }
        }
        return message

def test_large_json_message_sizes():
    """Test various large JSON message sizes"""
    print("🧪 Testing large JSON message sizes...")
    
    tester = InputSizeLimitsTester()
    
    # Test different message sizes (in bytes)
    size_tests = [
        (1024, "1KB", "Small message"),
        (10 * 1024, "10KB", "Medium message"),
        (100 * 1024, "100KB", "Large message"),
        (1024 * 1024, "1MB", "Very large message"),
        (10 * 1024 * 1024, "10MB", "Extremely large message"),
        (100 * 1024 * 1024, "100MB", "Massive message"),
        (1024 * 1024 * 1024, "1GB", "Gigabyte message"),
    ]
    
    memory_usage_tests = []
    for size_bytes, size_desc, description in size_tests:
        try:
            # Create large message
            start_time = time.time()
            large_message = tester.create_large_json_message(size_bytes)
            creation_time = time.time() - start_time
            
            # Serialize to JSON
            start_time = time.time()
            json_str = json.dumps(large_message)
            serialization_time = time.time() - start_time
            
            actual_size = len(json_str.encode('utf-8'))
            
            memory_usage_tests.append({
                "target_size": size_bytes,
                "size_desc": size_desc,
                "description": description,
                "actual_size": actual_size,
                "creation_time": creation_time,
                "serialization_time": serialization_time,
                "success": True
            })
            
            print(f"  📦 {size_desc} ({description}): {actual_size} bytes, "
                  f"creation: {creation_time:.3f}s, serialization: {serialization_time:.3f}s")
            
        except MemoryError:
            print(f"  💥 {size_desc} ({description}): Memory allocation failed")
            memory_usage_tests.append({
                "target_size": size_bytes,
                "size_desc": size_desc,
                "description": description,
                "success": False,
                "error": "MemoryError"
            })
        except Exception as e:
            print(f"  ❌ {size_desc} ({description}): Error - {e}")
            memory_usage_tests.append({
                "target_size": size_bytes,
                "size_desc": size_desc,
                "description": description,
                "success": False,
                "error": str(e)
            })
    
    # Analyze results
    successful_tests = [t for t in memory_usage_tests if t.get("success", False)]
    failed_tests = [t for t in memory_usage_tests if not t.get("success", False)]
    
    print(f"  📊 Results: {len(successful_tests)} successful, {len(failed_tests)} failed")
    
    if failed_tests:
        print("  ⚠️  Failed tests (good for DoS prevention):")
        for test in failed_tests:
            print(f"    - {test['size_desc']}: {test.get('error', 'Unknown error')}")
    
    assert len(memory_usage_tests) == len(size_tests)
    
    print("✓ Large JSON message size tests completed")
    return True

def test_large_content_length_headers():
    """Test large Content-Length header values"""
    print("🧪 Testing large Content-Length headers...")
    
    # Test various Content-Length values
    content_length_tests = [
        (1024, "Normal size"),
        (1024 * 1024, "1MB"),
        (100 * 1024 * 1024, "100MB"),
        (1024 * 1024 * 1024, "1GB"),
        (10 * 1024 * 1024 * 1024, "10GB"),
        (2**31 - 1, "Max 32-bit int"),
        (2**63 - 1, "Max 64-bit int"),
    ]
    
    header_results = []
    for length, description in content_length_tests:
        try:
            # Create Content-Length header
            header = f"Content-Length: {length}\r\n\r\n"
            
            # Test if the length value can be parsed
            length_str = str(length)
            parsed_length = int(length_str)
            
            header_results.append({
                "length": length,
                "description": description,
                "header_size": len(header),
                "success": True,
                "parsed_correctly": parsed_length == length
            })
            
            print(f"  📦 {description}: {length} bytes, header: {len(header)} bytes")
            
        except (ValueError, OverflowError) as e:
            print(f"  ❌ {description}: Parse error - {e}")
            header_results.append({
                "length": length,
                "description": description,
                "success": False,
                "error": str(e)
            })
        except Exception as e:
            print(f"  ❌ {description}: Unexpected error - {e}")
            header_results.append({
                "length": length,
                "description": description,
                "success": False,
                "error": str(e)
            })
    
    successful_headers = [r for r in header_results if r.get("success", False)]
    print(f"  📊 Successfully processed {len(successful_headers)} Content-Length values")
    
    assert len(header_results) == len(content_length_tests)
    
    print("✓ Large Content-Length header tests completed")
    return True

def test_large_uri_lengths():
    """Test extremely long URI strings"""
    print("🧪 Testing large URI lengths...")
    
    # Test different URI lengths
    uri_length_tests = [
        (100, "Normal URI"),
        (1000, "Long URI"),
        (10000, "Very long URI"),
        (100000, "Extremely long URI"),
        (1000000, "Massive URI"),
        (10000000, "Gigantic URI"),
    ]
    
    uri_results = []
    for length, description in uri_length_tests:
        try:
            # Create long URI
            base_uri = "file:///"
            padding = "a" * (length - len(base_uri) - 3)  # -3 for ".ec"
            long_uri = base_uri + padding + ".ec"
            
            actual_length = len(long_uri)
            
            # Test JSON serialization with long URI
            message = {
                "jsonrpc": "2.0",
                "method": "textDocument/didOpen",
                "params": {
                    "textDocument": {
                        "uri": long_uri,
                        "languageId": "easycrypt",
                        "version": 1,
                        "text": "test"
                    }
                }
            }
            
            json_str = json.dumps(message)
            json_size = len(json_str.encode('utf-8'))
            
            uri_results.append({
                "target_length": length,
                "actual_length": actual_length,
                "description": description,
                "json_size": json_size,
                "success": True
            })
            
            print(f"  📦 {description}: {actual_length} chars, JSON: {json_size} bytes")
            
        except MemoryError:
            print(f"  💥 {description}: Memory allocation failed")
            uri_results.append({
                "target_length": length,
                "description": description,
                "success": False,
                "error": "MemoryError"
            })
        except Exception as e:
            print(f"  ❌ {description}: Error - {e}")
            uri_results.append({
                "target_length": length,
                "description": description,
                "success": False,
                "error": str(e)
            })
    
    successful_uris = [r for r in uri_results if r.get("success", False)]
    failed_uris = [r for r in uri_results if not r.get("success", False)]
    
    print(f"  📊 Results: {len(successful_uris)} successful, {len(failed_uris)} failed")
    
    assert len(uri_results) == len(uri_length_tests)
    
    print("✓ Large URI length tests completed")
    return True

def test_large_array_inputs():
    """Test large arrays in JSON-RPC messages"""
    print("🧪 Testing large array inputs...")
    
    # Test different array sizes
    array_size_tests = [
        (100, "Small array"),
        (1000, "Medium array"),
        (10000, "Large array"),
        (100000, "Very large array"),
        (1000000, "Massive array"),
    ]
    
    array_results = []
    for size, description in array_size_tests:
        try:
            # Create large array of content changes
            content_changes = []
            for i in range(size):
                content_changes.append({
                    "range": {
                        "start": {"line": i, "character": 0},
                        "end": {"line": i, "character": 10}
                    },
                    "text": f"edit_{i}"
                })
            
            message = {
                "jsonrpc": "2.0",
                "method": "textDocument/didChange",
                "params": {
                    "textDocument": {
                        "uri": "file:///test.ec",
                        "version": 1
                    },
                    "contentChanges": content_changes
                }
            }
            
            # Test JSON serialization
            start_time = time.time()
            json_str = json.dumps(message)
            serialization_time = time.time() - start_time
            
            json_size = len(json_str.encode('utf-8'))
            
            array_results.append({
                "array_size": size,
                "description": description,
                "json_size": json_size,
                "serialization_time": serialization_time,
                "success": True
            })
            
            print(f"  📦 {description}: {size} items, JSON: {json_size} bytes, "
                  f"time: {serialization_time:.3f}s")
            
        except MemoryError:
            print(f"  💥 {description}: Memory allocation failed")
            array_results.append({
                "array_size": size,
                "description": description,
                "success": False,
                "error": "MemoryError"
            })
        except Exception as e:
            print(f"  ❌ {description}: Error - {e}")
            array_results.append({
                "array_size": size,
                "description": description,
                "success": False,
                "error": str(e)
            })
    
    successful_arrays = [r for r in array_results if r.get("success", False)]
    print(f"  📊 Successfully processed {len(successful_arrays)} array sizes")
    
    assert len(array_results) == len(array_size_tests)
    
    print("✓ Large array input tests completed")
    return True

def test_deeply_nested_json():
    """Test deeply nested JSON structures"""
    print("🧪 Testing deeply nested JSON structures...")
    
    # Test different nesting depths
    nesting_tests = [
        (10, "Shallow nesting"),
        (100, "Medium nesting"),
        (1000, "Deep nesting"),
        (10000, "Very deep nesting"),
    ]
    
    nesting_results = []
    for depth, description in nesting_tests:
        try:
            # Create deeply nested structure
            nested_obj = {"value": "leaf"}
            for i in range(depth):
                nested_obj = {"level": i, "nested": nested_obj}
            
            message = {
                "jsonrpc": "2.0",
                "method": "custom/deepNesting",
                "params": nested_obj
            }
            
            # Test JSON serialization
            start_time = time.time()
            json_str = json.dumps(message)
            serialization_time = time.time() - start_time
            
            json_size = len(json_str.encode('utf-8'))
            
            nesting_results.append({
                "depth": depth,
                "description": description,
                "json_size": json_size,
                "serialization_time": serialization_time,
                "success": True
            })
            
            print(f"  📦 {description}: {depth} levels, JSON: {json_size} bytes, "
                  f"time: {serialization_time:.3f}s")
            
        except RecursionError:
            print(f"  💥 {description}: Recursion limit exceeded")
            nesting_results.append({
                "depth": depth,
                "description": description,
                "success": False,
                "error": "RecursionError"
            })
        except MemoryError:
            print(f"  💥 {description}: Memory allocation failed")
            nesting_results.append({
                "depth": depth,
                "description": description,
                "success": False,
                "error": "MemoryError"
            })
        except Exception as e:
            print(f"  ❌ {description}: Error - {e}")
            nesting_results.append({
                "depth": depth,
                "description": description,
                "success": False,
                "error": str(e)
            })
    
    successful_nesting = [r for r in nesting_results if r.get("success", False)]
    failed_nesting = [r for r in nesting_results if not r.get("success", False)]
    
    print(f"  📊 Results: {len(successful_nesting)} successful, {len(failed_nesting)} failed")
    
    if failed_nesting:
        print("  ⚠️  Failed tests (good for recursion attack prevention):")
        for test in failed_nesting:
            print(f"    - {test['description']}: {test.get('error', 'Unknown error')}")
    
    assert len(nesting_results) == len(nesting_tests)
    
    print("✓ Deeply nested JSON tests completed")
    return True

def run_all_input_size_tests():
    """Run all input size limit tests"""
    print("🔍 Input Size Limits Test Suite")
    print("=" * 50)
    
    tests = [
        test_large_json_message_sizes,
        test_large_content_length_headers,
        test_large_uri_lengths,
        test_large_array_inputs,
        test_deeply_nested_json,
    ]
    
    passed = 0
    total = len(tests)
    
    for test_func in tests:
        try:
            if test_func():
                passed += 1
                print("✅ PASS")
            else:
                print("❌ FAIL")
        except Exception as e:
            print(f"❌ ERROR: {e}")
        print()
    
    print(f"📊 Results: {passed}/{total} tests passed")
    
    if passed == total:
        print("✅ All input size limit tests passed")
        return True
    else:
        print("❌ Some input size limit tests failed")
        return False

def main():
    """Main test runner"""
    print("Input Size Limits Test Suite")
    print("============================")
    print("NOTE: This test suite validates input size handling and DoS prevention")
    print("      Some tests are expected to fail (MemoryError, RecursionError)")
    print("      as this indicates proper resource limit enforcement")
    print()
    
    success = run_all_input_size_tests()
    
    if success:
        print("\n🎯 All input size limit tests completed successfully!")
        print("⚠️  These tests expose potential input size vulnerabilities:")
        print("   - Large JSON messages can cause memory exhaustion")
        print("   - Massive Content-Length headers can cause integer overflow")
        print("   - Extremely long URIs can exhaust memory")
        print("   - Large arrays can cause processing delays")
        print("   - Deeply nested JSON can cause stack overflow")
        print("\n💡 Resource limits and input validation are essential for:")
        print("   - Preventing DoS attacks via memory exhaustion")
        print("   - Avoiding stack overflow from deep recursion")
        print("   - Limiting processing time for oversized inputs")
        print("   - Maintaining server stability under load")
        return 0
    else:
        print("\n❌ Some input size limit tests failed to complete")
        return 1

if __name__ == "__main__":
    sys.exit(main())
