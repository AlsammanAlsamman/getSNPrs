#!/bin/bash

# Installation script for getSNPrs
# This script helps install dependencies and set up the tool

set -e

echo "=== getSNPrs Installation Script ==="
echo ""

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if command_exists apt-get; then
            echo "ubuntu"
        elif command_exists yum; then
            echo "rhel"
        elif command_exists dnf; then
            echo "fedora"
        else
            echo "linux"
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

# Function to install bcftools
install_bcftools() {
    local os=$(detect_os)
    
    echo "Installing bcftools..."
    
    case $os in
        ubuntu)
            echo "Using apt-get to install bcftools..."
            sudo apt-get update
            sudo apt-get install -y bcftools
            ;;
        rhel)
            echo "Using yum to install bcftools..."
            sudo yum install -y bcftools
            ;;
        fedora)
            echo "Using dnf to install bcftools..."
            sudo dnf install -y bcftools
            ;;
        macos)
            if command_exists brew; then
                echo "Using Homebrew to install bcftools..."
                brew install bcftools
            else
                echo "Please install Homebrew first: https://brew.sh/"
                echo "Then run: brew install bcftools"
                return 1
            fi
            ;;
        *)
            echo "Unsupported OS. Please install bcftools manually."
            echo "See: http://www.htslib.org/download/"
            return 1
            ;;
    esac
}

# Function to check dependencies
check_dependencies() {
    echo "Checking dependencies..."
    
    local missing_deps=()
    local deps=("wget" "gunzip" "sort" "uniq")
    
    for dep in "${deps[@]}"; do
        if ! command_exists "$dep"; then
            missing_deps+=("$dep")
        else
            echo "✓ $dep found"
        fi
    done
    
    # Check bcftools separately as it might need installation
    if command_exists bcftools; then
        echo "✓ bcftools found"
    else
        echo "✗ bcftools not found"
        read -p "Install bcftools? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_bcftools
        else
            missing_deps+=("bcftools")
        fi
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo ""
        echo "Missing dependencies: ${missing_deps[*]}"
        echo "Please install these dependencies manually and run this script again."
        return 1
    fi
    
    echo ""
    echo "✓ All dependencies are satisfied!"
    return 0
}

# Function to set up getSNPrs
setup_getSNPrs() {
    echo "Setting up getSNPrs..."
    
    # Make script executable
    if [ -f "getSNPrs.sh" ]; then
        chmod +x getSNPrs.sh
        echo "✓ Made getSNPrs.sh executable"
    else
        echo "✗ getSNPrs.sh not found in current directory"
        return 1
    fi
    
    # Make test script executable
    if [ -f "test_getSNPrs.sh" ]; then
        chmod +x test_getSNPrs.sh
        echo "✓ Made test_getSNPrs.sh executable"
    fi
    
    # Create examples directory if it doesn't exist
    if [ ! -d "examples" ]; then
        mkdir -p examples
        echo "✓ Created examples directory"
    fi
    
    echo ""
    echo "Setup completed successfully!"
}

# Function to test installation
test_installation() {
    echo "Testing installation..."
    
    # Test basic functionality
    echo "chr1	998371" | ./getSNPrs.sh -i /dev/stdin --help > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "✓ getSNPrs.sh is working"
    else
        echo "✗ getSNPrs.sh test failed"
        return 1
    fi
    
    echo ""
    echo "Installation test passed!"
}

# Function to show next steps
show_next_steps() {
    echo ""
    echo "=== Installation Complete ==="
    echo ""
    echo "Next steps:"
    echo "1. Test the installation:"
    echo "   ./test_getSNPrs.sh"
    echo ""
    echo "2. Try a basic example:"
    echo "   echo 'chr1 998371' | ./getSNPrs.sh -i /dev/stdin"
    echo ""
    echo "3. View help for more options:"
    echo "   ./getSNPrs.sh --help"
    echo ""
    echo "4. Add to PATH for global access (optional):"
    echo "   export PATH=\"\$(pwd):\$PATH\""
    echo "   # Add the above line to ~/.bashrc to make it permanent"
    echo ""
}

# Main installation process
main() {
    echo "This script will help you install getSNPrs and its dependencies."
    echo ""
    
    # Check if we're in the right directory
    if [ ! -f "getSNPrs.sh" ]; then
        echo "Error: getSNPrs.sh not found in current directory"
        echo "Please run this script from the getSNPrs directory"
        exit 1
    fi
    
    # Check dependencies
    if ! check_dependencies; then
        exit 1
    fi
    
    # Set up getSNPrs
    if ! setup_getSNPrs; then
        exit 1
    fi
    
    # Test installation
    if ! test_installation; then
        echo "Warning: Installation test failed, but dependencies are installed."
        echo "You may need to manually check the setup."
    fi
    
    # Show next steps
    show_next_steps
}

# Run main function
main "$@"
