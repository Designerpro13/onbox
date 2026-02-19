#!/bin/bash
#
# onbox installer
# Usage: bash install.sh
#

set -e

echo "📦 Installing onbox..."

# Check prerequisites
if ! command -v rclone &> /dev/null; then
    echo "❌ rclone not found. Install with:"
    echo "   Ubuntu/Debian: sudo apt install rclone"
    echo "   macOS: brew install rclone"
    exit 1
fi

# Install CLI
echo "📁 Installing CLI to /usr/local/bin/onbox..."
sudo cp bin/onbox /usr/local/bin/
sudo chmod +x /usr/local/bin/onbox

# Install systemd service
echo "⚙️  Installing systemd service..."
mkdir -p ~/.config/systemd/user
cp systemd/onbox-mount.service ~/.config/systemd/user/onbox-mount.service

# Reload systemd
systemctl --user daemon-reload

echo ""
echo "✅ Installation complete!"
echo ""
echo "Next steps:"
echo "  1. Configure rclone:"
echo "     rclone config"
echo ""
echo "  2. Test it:"
echo "     onbox ls"
echo ""
echo "  3. (Optional) Survive logout:"
echo "     loginctl enable-linger \$USER"
echo ""
echo "Happy uploading! 🚀"
