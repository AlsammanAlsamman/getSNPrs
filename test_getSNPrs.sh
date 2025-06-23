#!/bin/bash

# Test script for getSNPrs
# This script demonstrates various usage scenarios

echo "=== getSNPrs Test Script ==="
echo ""

# Check if getSNPrs.sh exists
if [ ! -f "./getSNPrs.sh" ]; then
    echo "Error: getSNPrs.sh not found in current directory"
    exit 1
fi

# Make sure it's executable
chmod +x ./getSNPrs.sh

echo "1. Testing help message:"
echo "========================"
./getSNPrs.sh --help
echo ""

echo "2. Testing with chr-prefixed format (basic output):"
echo "================================================="
head -n 3 examples/test_snps_chr.txt | ./getSNPrs.sh -i /dev/stdin -q --no-report
echo ""

echo "3. Testing with numeric format (basic output):"
echo "=============================================="
head -n 3 examples/test_snps_numeric.txt | ./getSNPrs.sh -i /dev/stdin -q --no-report
echo ""

echo "4. Testing with INFO fields:"
echo "============================"
echo "chr1	998371" | ./getSNPrs.sh -i /dev/stdin -q --no-report --info "AC,AF,DP"
echo ""

echo "5. Testing with mixed results (found and not found):"
echo "==================================================="
./getSNPrs.sh -i examples/test_mixed_results.txt -q --no-report
echo ""

echo "6. Testing report generation:"
echo "============================="
echo "chr1	998371" | ./getSNPrs.sh -i /dev/stdin -q -o test_output.txt --report test_report.txt
if [ -f "test_report.txt" ]; then
    echo "Report generated successfully:"
    head -n 15 test_report.txt
    echo "..."
    rm -f test_report.txt test_output.txt
else
    echo "No report file created"
fi
echo ""

echo "7. Testing delimiter detection:"
echo "==============================="
echo "Tab-separated input:"
echo -e "chr1\t998371\nchr1\t998395" | ./getSNPrs.sh -i /dev/stdin -q --no-report
echo ""

echo "Space-separated input:"
echo "chr1 998371" | ./getSNPrs.sh -i /dev/stdin -q --no-report
echo ""

echo "8. Testing output to file:"
echo "========================="
echo "chr1	998371" | ./getSNPrs.sh -i /dev/stdin -o test_output.txt -q --no-report
if [ -f "test_output.txt" ]; then
    echo "Output file created successfully:"
    cat test_output.txt
    rm -f test_output.txt
else
    echo "No output file created (no matches found)"
fi
echo ""

echo "9. Testing chromosome format conversion:"
echo "======================================="
echo "Input: 23 (should be treated as X chromosome)"
echo "23	123456" | ./getSNPrs.sh -i /dev/stdin -q --no-report
echo ""

echo "10. Testing error handling:"
echo "==========================="
echo "Testing with non-existent file:"
./getSNPrs.sh -i non_existent_file.txt 2>&1 | head -n 1
echo ""

echo "11. Performance test with larger file:"
echo "======================================"
# Create a temporary large file
temp_file=$(mktemp)
for i in {1..50}; do
    echo "chr1	99$((8371 + i))" >> "$temp_file"
done

echo "Processing 50 SNPs..."
./getSNPrs.sh -i "$temp_file" -q --no-report -o temp_large_output.txt
if [ -f "temp_large_output.txt" ]; then
    line_count=$(wc -l < temp_large_output.txt)
    echo "Found matches for: $line_count SNPs"
    rm -f temp_large_output.txt
else
    echo "No matches found"
fi

# Cleanup
rm -f "$temp_file"
echo ""

echo "=== Test completed ==="
echo ""
echo "Note: Some tests may show 'no matches found' if the reference"
echo "file is not available or if the test coordinates don't exist"
echo "in the reference. This is normal for testing purposes."
