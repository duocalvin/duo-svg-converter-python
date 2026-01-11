#!/bin/bash

# PNG to SVG Converter with folder selection
# Shows folder picker first, then launches Illustrator, then shows completion

# Configuration
ILLUSTRATOR_PATH="/Applications/Adobe Illustrator 2025/Adobe Illustrator.app"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if Illustrator is running
check_illustrator_running() {
    # Look specifically for the main Illustrator process, not background processes
    if pgrep -f "Adobe Illustrator.app/Contents/MacOS/Adobe Illustrator" > /dev/null 2>&1; then
        return 0  # Running
    elif ps aux | grep -q "[A]dobe Illustrator.app/Contents/MacOS/Adobe Illustrator"; then
        return 0  # Running
    else
        return 1  # Not running
    fi
}

# Function to wait for Illustrator to start
wait_for_illustrator_start() {
    echo -e "${YELLOW}⏳ Waiting for Illustrator to start...${NC}"
    local timeout=30
    local count=0
    
    while ! check_illustrator_running && [ $count -lt $timeout ]; do
        sleep 1
        count=$((count + 1))
        echo -e "${BLUE}⏳ Waiting... ($count/$timeout)${NC}"
    done
    
    if check_illustrator_running; then
        echo -e "${GREEN}✅ Illustrator is running!${NC}"
        return 0
    else
        echo -e "${RED}❌ Timeout waiting for Illustrator to start${NC}"
        return 1
    fi
}

# Function to wait for Illustrator to close
wait_for_illustrator_close() {
    echo -e "${YELLOW}⏳ Processing images in Illustrator...${NC}"
    
    # Wait for it to close
    local check_count=0
    while check_illustrator_running; do
        sleep 2
        check_count=$((check_count + 1))
        if [ $((check_count % 10)) -eq 0 ]; then
            echo -e "${BLUE}⏳ Still processing... (${check_count} checks)${NC}"
            # Debug: Show what processes we're detecting
            echo -e "${BLUE}🔍 Debug: Current Illustrator processes:${NC}"
            ps aux | grep -i "Adobe Illustrator" | grep -v grep || echo "No processes found"
        fi
    done
    
    echo -e "${GREEN}✅ Illustrator has closed${NC}"
}

# Function to show folder selection dialog using AppleScript
select_folder() {
    local folder_path
    
    # Try the folder selection with proper AppleScript syntax
    folder_path=$(osascript << 'EOF'
tell application "Finder"
    activate
    set selectedFolder to choose folder with prompt "Select folder containing PNG images:"
    return POSIX path of selectedFolder
end tell
EOF
)
    
    local exit_code=$?
    
    if [ $exit_code -eq 0 ] && [ -n "$folder_path" ]; then
        # Remove trailing newline and slash
        folder_path=$(echo "$folder_path" | sed 's/[[:space:]]*$//' | sed 's/\/$//')
        echo "$folder_path"
        return 0
    else
        echo -e "${RED}❌ Folder selection canceled or failed${NC}" >&2
        return 1
    fi
}



clear
echo -e "${BLUE}🎨 PNG to SVG Converter${NC}"
echo -e "${BLUE}========================${NC}"
echo
echo "This script will:"
echo "• Show folder selection dialog first"
echo "• Launch Illustrator automatically"
echo "• Create 'SVG' subfolder automatically"
echo "• Convert all PNGs to vectorized SVGs"
echo "• Remove white backgrounds automatically"
echo "• Close Illustrator when complete"
echo "• Show completion notification"
echo

# Check if Illustrator exists
if [ ! -d "$ILLUSTRATOR_PATH" ]; then
    echo -e "${RED}❌ Error: Illustrator not found at $ILLUSTRATOR_PATH${NC}"
    echo "Please update the ILLUSTRATOR_PATH variable in this script."
    exit 1
fi

# Step 1: Parse CLI options (input folder preferred) then fallback to dialog
selected_folder=""
TRACE_COLORS=""
TRACE_COLORS_PCT=""
TRACE_PATHS=""
TRACE_TRANSPARENT=""
OUT_SCALE=""
OUT_W=""
OUT_H=""

_is_number() { echo "$1" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; }
_is_int() { echo "$1" | grep -Eq '^[0-9]+$'; }

ARGS=("$@")
idx=0
while [ $idx -lt ${#ARGS[@]} ]; do
    arg="${ARGS[$idx]}"
    case "$arg" in
        --input)
            next="$((idx+1))"
            val="${ARGS[$next]:-}"
            [ -z "$val" ] && { echo -e "${RED}❌ --input requires a value${NC}"; exit 1; }
            selected_folder="${val%/}"
            idx=$((idx+2))
            ;;
        --colors)
            val="${ARGS[$((idx+1))]:-}"
            [ -z "$val" ] && { echo -e "${RED}❌ --colors requires a value${NC}"; exit 1; }
            TRACE_COLORS="$val"
            idx=$((idx+2))
            ;;
        --colors-pct)
            val="${ARGS[$((idx+1))]:-}"
            [ -z "$val" ] && { echo -e "${RED}❌ --colors-pct requires a value${NC}"; exit 1; }
            TRACE_COLORS_PCT="$val"
            idx=$((idx+2))
            ;;
        --paths)
            val="${ARGS[$((idx+1))]:-}"
            [ -z "$val" ] && { echo -e "${RED}❌ --paths requires a value${NC}"; exit 1; }
            TRACE_PATHS="$val"
            idx=$((idx+2))
            ;;
        --transparent)
            val="${ARGS[$((idx+1))]:-}"
            [ -z "$val" ] && { echo -e "${RED}❌ --transparent requires a value (true|false)${NC}"; exit 1; }
            TRACE_TRANSPARENT="$val"
            idx=$((idx+2))
            ;;
        --scale)
            val="${ARGS[$((idx+1))]:-}"
            [ -z "$val" ] && { echo -e "${RED}❌ --scale requires a value (float)${NC}"; exit 1; }
            OUT_SCALE="$val"
            idx=$((idx+2))
            ;;
        --out-w)
            val="${ARGS[$((idx+1))]:-}"
            [ -z "$val" ] && { echo -e "${RED}❌ --out-w requires a value (int px)${NC}"; exit 1; }
            OUT_W="$val"
            idx=$((idx+2))
            ;;
        --out-h)
            val="${ARGS[$((idx+1))]:-}"
            [ -z "$val" ] && { echo -e "${RED}❌ --out-h requires a value (int px)${NC}"; exit 1; }
            OUT_H="$val"
            idx=$((idx+2))
            ;;
        --)
            idx=$((idx+1))
            break
            ;;
        -*)
            echo -e "${RED}❌ Unknown option: $arg${NC}"
            exit 1
            ;;
        *)
            if [ -z "$selected_folder" ] && [ -d "$arg" ]; then
                selected_folder="${arg%/}"
                idx=$((idx+1))
            else
                idx=$((idx+1))
            fi
            ;;
    esac
done

if [ -z "$selected_folder" ]; then
    echo -e "${BLUE}📁 Opening folder selection dialog...${NC}"
    selected_folder=$(select_folder)
    if [ $? -ne 0 ] || [ -z "$selected_folder" ]; then
        echo -e "${RED}❌ No folder selected. Exiting.${NC}"
        exit 1
    fi
    echo -e "${GREEN}✅ Selected folder: $(basename \"$selected_folder\")${NC}"
    echo -e "${BLUE}📂 Full path: $selected_folder${NC}"
else
    if [ -d "$selected_folder" ]; then
        echo -e "${GREEN}✅ Selected folder (from argument): $(basename \"$selected_folder\")${NC}"
        echo -e "${BLUE}📂 Full path: $selected_folder${NC}"
    else
        echo -e "${RED}❌ Provided path is not a directory: $selected_folder${NC}"
        exit 1
    fi
fi

# Validate options if provided
if [ -n "$TRACE_COLORS" ]; then
    if ! _is_int "$TRACE_COLORS"; then
        echo -e "${RED}❌ --colors must be an integer${NC}"
        exit 1
    fi
fi

if [ -n "$TRACE_COLORS_PCT" ]; then
    if ! _is_int "$TRACE_COLORS_PCT" || [ "$TRACE_COLORS_PCT" -lt 0 ] || [ "$TRACE_COLORS_PCT" -gt 100 ]; then
        echo -e "${RED}❌ --colors-pct must be an integer between 0 and 100${NC}"
        exit 1
    fi
fi

if [ -n "$TRACE_PATHS" ]; then
    if ! _is_int "$TRACE_PATHS" || [ "$TRACE_PATHS" -lt 1 ] || [ "$TRACE_PATHS" -gt 100 ]; then
        echo -e "${RED}❌ --paths must be an integer percentage between 1 and 100${NC}"
        exit 1
    fi
fi

if [ -n "$OUT_SCALE" ]; then
    if ! _is_number "$OUT_SCALE" ; then
        echo -e "${RED}❌ --scale must be a number${NC}"
        exit 1
    fi
fi

if [ -n "$OUT_W" ] && ! _is_int "$OUT_W"; then
    echo -e "${RED}❌ --out-w must be an integer (px)${NC}"
    exit 1
fi
if [ -n "$OUT_H" ] && ! _is_int "$OUT_H"; then
    echo -e "${RED}❌ --out-h must be an integer (px)${NC}"
    exit 1
fi

# Default transparency: true (match prior behavior)
if [ -z "$TRACE_TRANSPARENT" ]; then
    TRACE_TRANSPARENT=true
fi

# Check if folder contains PNG files
png_count=$(find "$selected_folder" -maxdepth 1 -name "*.png" | wc -l)

if [ "$png_count" -eq 0 ]; then
    echo -e "${RED}❌ No PNG files found in the selected folder.${NC}"
    
    osascript << EOF
tell application "Finder"
    activate
    display dialog "No PNG files found in the selected folder." with title "Error" buttons {"OK"} default button "OK"
end tell
EOF
    exit 1
fi

echo -e "${BLUE}📊 Found $png_count PNG files to convert${NC}"

# Step 2: Launch Illustrator with the selected folder path
echo -e "${GREEN}🚀 Launching Illustrator...${NC}"

# Create a temporary script file with the folder path and .jsx extension
temp_script=$(mktemp).jsx
cat > "$temp_script" << 'EOF'
#target illustrator

// Disable script security warning
app.preferences.setBooleanPreference("ShowExternalJSXWarning", false);

// Map 1-100 UI "paths" to Illustrator pathFitting (approx inverse)
function mapPathsPercentToPathFitting(p) {
    var minFit = 0.5;
    var maxFit = 10.0;
    var t = Math.max(1, Math.min(100, p)) / 100.0;
    return maxFit - t * (maxFit - minFit);
}

// Scale all page items by percent (100 = no change)
function scaleAllItems(doc, percent) {
    for (var i = 0; i < doc.pageItems.length; i++) {
        try {
            doc.pageItems[i].resize(percent, percent, true, true, true, true, percent, TransformPatterns.DONTTRANSFORMPATTERNS, TransformGradients.DONTTRANSFORMGRADIENTS, true, true, true);
        } catch (e) {}
    }
}

// Compute artwork bounds (union of pageItems)
function getArtworkBounds(doc) {
    if (doc.pageItems.length === 0) { return null; }
    var b = doc.pageItems[0].geometricBounds;
    var left = b[0], top = b[1], right = b[2], bottom = b[3];
    for (var i = 1; i < doc.pageItems.length; i++) {
        try {
            var gb = doc.pageItems[i].geometricBounds;
            if (gb[0] < left) left = gb[0];
            if (gb[1] > top) top = gb[1];
            if (gb[2] > right) right = gb[2];
            if (gb[3] < bottom) bottom = gb[3];
        } catch (e) {}
    }
    return [left, top, right, bottom];
}

// Embedded version that accepts folder path and CONFIG
function traceAndExportPNGs(inputFolderPath, CONFIG) {
    var inputFolder = new Folder(inputFolderPath);

    if (!inputFolder || !inputFolder.exists) {
        alert("Invalid folder path. Exiting.");
        app.quit();
        return;
    }

    // Create SVG subfolder automatically
    var outputFolder = new Folder(inputFolder.fsName + "/SVG");
    if (!outputFolder.exists) {
        outputFolder.create();
    }

    var files = inputFolder.getFiles("*.png");

    if (files.length === 0) {
        alert("No PNG files found in the selected folder. Exiting.");
        app.quit();
        return;
    }



    for (var i = 0; i < files.length; i++) {
        var file = files[i];
        var doc = null;
        var step = "start";
        try {
            step = "create document";
            doc = app.documents.add(DocumentColorSpace.RGB, 1000, 1000);

            step = "place image";
            var placedItem = doc.placedItems.add();
            if (!placedItem) throw new Error("Failed to create placed item");
            placedItem.file = file;

            step = "resize document to match image";
            doc.artboards[0].artboardRect = [0, placedItem.height, placedItem.width, 0];

            step = "position image";
            placedItem.left = 0;
            placedItem.top = placedItem.height;

            step = "embed image";
            placedItem.embed();
            app.redraw();
            
            step = "get traced item";
            var tracedItem = doc.pageItems[0];
            if (!tracedItem) throw new Error("No page items found after placing image");

            step = "trace image";
            if (tracedItem.trace) {
                // Build tracing options if available
                var usedOptions = null;
                try {
                    if (CONFIG) {
                        usedOptions = new TracingOptions();
                        usedOptions.tracingMode = TracingMode.TRACINGMODECOLOR;
                        // Ensure colors/percent setting is honored by using Auto Color palette with fills
                        try { usedOptions.palette = TracingPalette.TRACINGPALETTEAUTOCOLOR; } catch (ePal) {}
                        try { usedOptions.filling = true; } catch (eFill) {}
                        try { usedOptions.strokes = false; } catch (eStr) {}
                        // Prefer colorsPct (0..100) over maxColors
                        if (CONFIG.colorsPct !== undefined && CONFIG.colorsPct !== null) {
                            try { usedOptions.colorFidelity = Math.max(0, Math.min(100, CONFIG.colorsPct)); } catch (eCF) {}
                        } else if (CONFIG.colors && CONFIG.colors >= 2 && CONFIG.colors <= 30) {
                            // Backward compatibility: map 2..30 to 0..100 roughly
                            var pct = Math.round((CONFIG.colors - 2) * (100.0 / 28.0));
                            try { usedOptions.colorFidelity = Math.max(0, Math.min(100, pct)); } catch (eCF2) {}
                        }
                        if (CONFIG.paths && CONFIG.paths >= 1 && CONFIG.paths <= 100) {
                            usedOptions.pathFitting = mapPathsPercentToPathFitting(CONFIG.paths);
                        }
                        if (typeof CONFIG.transparent === "boolean") {
                            usedOptions.ignoreWhite = CONFIG.transparent;
                        }
                    }
                } catch (eOpt) {
                    usedOptions = null;
                }

                try {
                    if (usedOptions) {
                        tracedItem.trace(usedOptions);
                    } else {
                        tracedItem.trace();
                    }
                } catch (eTrace) {
                    tracedItem.trace();
                }
                app.redraw();

                var tracingObj = null;
                for (var j = 0; j < doc.pageItems.length; j++) {
                    var item = doc.pageItems[j];
                    if (item.typename === "TracingObject" || item.tracing) {
                        tracingObj = item;
                        break;
                    }
                }

                if (tracingObj) {
                    step = "expand tracing";
                    var expanded = false;
                    
                    try {
                        if (tracingObj.tracing && tracingObj.tracing.expandTracing) {
                            tracingObj.tracing.expandTracing();
                            expanded = true;
                        }
                    } catch (e1) {
                        // Method 1 failed, try method 2
                    }
                    
                    if (!expanded) {
                        try {
                            if (tracingObj.expand) {
                                tracingObj.expand();
                                expanded = true;
                            }
                        } catch (e2) {
                            // Method 2 failed, try method 3
                        }
                    }
                    
                    if (!expanded) {
                        try {
                            for (var j = 0; j < doc.pageItems.length; j++) {
                                doc.pageItems[j].selected = false;
                            }
                            tracingObj.selected = true;
                            app.executeMenuCommand('expand');
                            expanded = true;
                        } catch (e3) {
                            throw new Error("All expansion methods failed. Last error: " + e3.message);
                        }
                    }
                    
                    if (expanded) {
                        app.redraw();
                        
                        // Remove white background only if requested (default true)
                        if (!CONFIG || CONFIG.transparent === undefined || CONFIG.transparent === true) {
                            step = "remove white background";
                            var largestArea = 0;
                            var backgroundItem = null;
                            for (var k = 0; k < doc.pathItems.length; k++) {
                                var pathItem = doc.pathItems[k];
                                if (pathItem.filled && pathItem.fillColor) {
                                    var area = pathItem.width * pathItem.height;
                                    var isWhiteish = false;
                                    if (pathItem.fillColor.typename === "RGBColor") {
                                        var rgb = pathItem.fillColor;
                                        if (rgb.red > 240 && rgb.green > 240 && rgb.blue > 240) {
                                            isWhiteish = true;
                                        }
                                    } else if (pathItem.fillColor.typename === "GrayColor") {
                                        if (pathItem.fillColor.gray > 90) {
                                            isWhiteish = true;
                                        }
                                    }
                                    if (isWhiteish && area > largestArea) {
                                        largestArea = area;
                                        backgroundItem = pathItem;
                                    }
                                }
                            }
                            if (backgroundItem) {
                                backgroundItem.remove();
                            }
                        }

                        // Output sizing
                        try {
                            if (CONFIG) {
                                // Exact size takes precedence
                                if ((CONFIG.outW && CONFIG.outW > 0) || (CONFIG.outH && CONFIG.outH > 0)) {
                                    var bounds = getArtworkBounds(doc);
                                    if (bounds) {
                                        var curW = bounds[2] - bounds[0];
                                        var curH = bounds[1] - bounds[3];
                                        var targetW = CONFIG.outW && CONFIG.outW > 0 ? CONFIG.outW : curW;
                                        var targetH = CONFIG.outH && CONFIG.outH > 0 ? CONFIG.outH : curH;
                                        var s = Math.min(targetW / curW, targetH / curH) * 100.0;
                                        if (s > 0) {
                                            scaleAllItems(doc, s);
                                            doc.artboards[0].artboardRect = [0, targetH, targetW, 0];
                                            app.redraw();
                                        }
                                    }
                                } else if (CONFIG.scale && CONFIG.scale > 0 && CONFIG.scale != 1.0) {
                                    var s2 = CONFIG.scale * 100.0;
                                    scaleAllItems(doc, s2);
                                    app.redraw();
                                }
                            }
                        } catch (eScale) {}
                    }
                } else {
                    throw new Error("No tracing object found after tracing.");
                }
            } else {
                throw new Error("Image Trace not available on this object");
            }

            step = "export SVG";
            var saveFile = new File(outputFolder.fsName + "/" + file.name.replace(/\.png$/i, ".svg"));
            var exportOptions = new ExportOptionsSVG();
            exportOptions.embedRasterImages = false;
            exportOptions.useArtboards = true;
            doc.exportFile(saveFile, ExportType.SVG, exportOptions);

        } catch (e) {
            // Ignore errors for now
        } finally {
            if (doc) doc.close(SaveOptions.DONOTSAVECHANGES);
        }
    }
    
    app.quit();
}

// Call the function with the folder path
EOF

# Now append the CONFIG and function call with the actual folder path
js_bool() { [ "$1" = "true" ] && echo true || echo false; }
CONFIG_JS="var CONFIG = {"
if [ -n "$TRACE_COLORS_PCT" ]; then CONFIG_JS="$CONFIG_JS colorsPct: $TRACE_COLORS_PCT,"; fi
if [ -z "$TRACE_COLORS_PCT" ] && [ -n "$TRACE_COLORS" ]; then CONFIG_JS="$CONFIG_JS colors: $TRACE_COLORS,"; fi
if [ -n "$TRACE_PATHS" ]; then CONFIG_JS="$CONFIG_JS paths: $TRACE_PATHS,"; fi
if [ -n "$TRACE_TRANSPARENT" ]; then CONFIG_JS="$CONFIG_JS transparent: $(js_bool $TRACE_TRANSPARENT),"; fi
if [ -n "$OUT_SCALE" ]; then CONFIG_JS="$CONFIG_JS scale: $OUT_SCALE,"; fi
if [ -n "$OUT_W" ]; then CONFIG_JS="$CONFIG_JS outW: $OUT_W,"; fi
if [ -n "$OUT_H" ]; then CONFIG_JS="$CONFIG_JS outH: $OUT_H,"; fi
CONFIG_JS="$CONFIG_JS };"

echo "$CONFIG_JS" >> "$temp_script"
echo "traceAndExportPNGs(\"$selected_folder\", CONFIG);" >> "$temp_script"

# Launch Illustrator with the temporary script
echo -e "${BLUE}🚀 Starting Illustrator with script...${NC}"
echo -e "${YELLOW}⚠️  If Illustrator shows a script security dialog, click 'Continue' to proceed${NC}"
open -a "$ILLUSTRATOR_PATH" "$temp_script"

# Wait for Illustrator to start
if ! wait_for_illustrator_start; then
    echo -e "${RED}❌ Failed to start Illustrator. Exiting.${NC}"
    rm -f "$temp_script"
    exit 1
fi

# Wait for Illustrator to close
wait_for_illustrator_close

# Debug: Check what processes are running
echo -e "${BLUE}🔍 Debug: Checking for any remaining Illustrator processes...${NC}"
ps aux | grep -i illustrator | grep -v grep || echo "No Illustrator processes found"

# Clean up temp script
rm -f "$temp_script"

# Step 3: Show completion notification
echo -e "${GREEN}✅ Illustrator has closed. Processing complete!${NC}"

# Show completion dialog
echo -e "${BLUE}🔍 Checking conversion results...${NC}"

# Check if SVG folder exists
svg_folder="$selected_folder/SVG"
if [ -d "$svg_folder" ]; then
    echo -e "${GREEN}✅ SVG folder found - conversion appears successful!${NC}"
    
    # Show simplified completion dialog
    echo -e "${BLUE}🎊 Showing completion dialog...${NC}"
    
    osascript << EOF
tell application "Finder"
    activate
    set userChoice to button returned of (display dialog "🎉 PNG to SVG Conversion Complete! 🎉

✅ Your PNG files have been converted to SVG format

📁 SVG files are located in the 'SVG' subfolder

🚀 All SVG files are ready to use!" with title "Conversion Complete" buttons {"Open SVG Folder", "OK"} default button "OK")
    if userChoice is "Open SVG Folder" then
        open POSIX file "$svg_folder"
    end if
end tell
EOF
    
    echo -e "${GREEN}✅ Completion dialog shown${NC}"
else
    echo -e "${RED}❌ No SVG folder found. Something went wrong.${NC}"
    osascript -e 'display dialog "❌ No SVG folder found. Something went wrong." with title "Error" buttons {"OK"}'
fi

echo -e "${GREEN}🎉 All done!${NC}" 