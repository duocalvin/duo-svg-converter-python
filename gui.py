import os
import sys
import shutil
from typing import Optional

from PyQt6.QtCore import Qt, QProcess, QSettings
from PyQt6.QtWidgets import (
    QApplication,
    QWidget,
    QVBoxLayout,
    QHBoxLayout,
    QGridLayout,
    QLabel,
    QLineEdit,
    QPushButton,
    QFileDialog,
    QPlainTextEdit,
    QMessageBox,
    QCheckBox,
    QGroupBox,
    QToolButton,
    QFrame,
    QSlider,
    QSpinBox,
    QDoubleSpinBox,
    QRadioButton,
    QButtonGroup,
)


def get_resource_path(relative_name: str) -> Optional[str]:
    """Return absolute path for a bundled resource (supports PyInstaller) or None if missing."""
    base_path = getattr(sys, "_MEIPASS", None)
    search_roots = []
    if base_path:
        search_roots.append(base_path)
    # Development fallback: directory of this file
    search_roots.append(os.path.dirname(os.path.abspath(__file__)))

    for root in search_roots:
        candidate = os.path.join(root, relative_name)
        if os.path.exists(candidate):
            return candidate
    return None


class SvgConverterApp(QWidget):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("Duo SVG Converter")

        self.process: Optional[QProcess] = None
        self.settings = QSettings("duolingo", "duo-svg-converter")

        # Trace settings widgets (initialized in _build_ui)
        self.use_default_colors_cb: Optional[QCheckBox] = None
        self.colors_slider: Optional[QSlider] = None
        self.colors_spin: Optional[QSpinBox] = None

        self.use_default_paths_cb: Optional[QCheckBox] = None
        self.paths_slider: Optional[QSlider] = None
        self.paths_spin: Optional[QSpinBox] = None

        self.transparent_cb: Optional[QCheckBox] = None

        self.scale_radio: Optional[QRadioButton] = None
        self.scale_spin: Optional[QDoubleSpinBox] = None
        self.exact_radio: Optional[QRadioButton] = None
        self.width_spin: Optional[QSpinBox] = None
        self.height_spin: Optional[QSpinBox] = None

        self._build_ui()
        self._restore_last_dirs()

    def _build_ui(self) -> None:
        layout = QVBoxLayout()
        layout.setSpacing(10)

        # Input directory chooser
        input_row = QHBoxLayout()
        input_label = QLabel("Input directory (PNGs):")
        self.input_edit = QLineEdit()
        self.input_edit.setReadOnly(True)
        browse_input_btn = QPushButton("Browse…")
        browse_input_btn.clicked.connect(self._browse_input)
        input_row.addWidget(input_label)
        input_row.addWidget(self.input_edit, 1)
        input_row.addWidget(browse_input_btn)
        layout.addLayout(input_row)

        # Output directory chooser
        output_row = QHBoxLayout()
        output_label = QLabel("Output directory:")
        self.output_edit = QLineEdit()
        self.output_edit.setReadOnly(True)
        browse_output_btn = QPushButton("Browse…")
        browse_output_btn.clicked.connect(self._browse_output)
        output_row.addWidget(output_label)
        output_row.addWidget(self.output_edit, 1)
        output_row.addWidget(browse_output_btn)
        layout.addLayout(output_row)

        self.open_when_done = QCheckBox("Open output folder when done")
        self.open_when_done.setChecked(True)
        layout.addWidget(self.open_when_done)

        # No additional note needed now that the script accepts an input path argument

        # Collapsible Image Trace Settings
        layout.addWidget(self._build_trace_settings_group())

        # Controls
        controls_row = QHBoxLayout()
        self.run_button = QPushButton("Run Conversion")
        self.run_button.clicked.connect(self._run_conversion)
        controls_row.addStretch(1)
        controls_row.addWidget(self.run_button)
        layout.addLayout(controls_row)

        # Log output
        self.log = QPlainTextEdit()
        self.log.setReadOnly(True)
        self.log.setMinimumHeight(220)
        layout.addWidget(self.log, 1)

        self.setLayout(layout)

    def _build_trace_settings_group(self) -> QWidget:
        # Collapsible header
        container = QWidget()
        v = QVBoxLayout(container)
        v.setContentsMargins(0, 0, 0, 0)
        header = QToolButton()
        header.setText("Image Trace Settings")
        header.setToolButtonStyle(Qt.ToolButtonStyle.ToolButtonTextBesideIcon)
        header.setArrowType(Qt.ArrowType.RightArrow)
        header.setCheckable(True)
        header.setChecked(False)
        header.toggled.connect(lambda checked: header.setArrowType(Qt.ArrowType.DownArrow if checked else Qt.ArrowType.RightArrow))
        v.addWidget(header)

        content = QGroupBox()
        content.setTitle("")
        content.setFlat(True)
        content.setVisible(False)
        header.toggled.connect(content.setVisible)
        v.addWidget(content)

        grid = QGridLayout()
        grid.setColumnStretch(2, 1)
        content.setLayout(grid)

        # Colors
        self.use_default_colors_cb = QCheckBox("Use default")
        self.use_default_colors_cb.setChecked(True)
        self.use_default_colors_cb.toggled.connect(self._on_colors_default_toggled)
        colors_label = QLabel("Colors (%):")
        low_lbl = QLabel("Low")
        high_lbl = QLabel("High")
        self.colors_slider = QSlider(Qt.Orientation.Horizontal)
        self.colors_slider.setRange(0, 100)
        self.colors_slider.setValue(50)
        self.colors_slider.setEnabled(False)
        self.colors_spin = QSpinBox()
        self.colors_spin.setRange(0, 100)
        self.colors_spin.setSuffix("%")
        self.colors_spin.setValue(50)
        self.colors_spin.setEnabled(False)
        self.colors_slider.valueChanged.connect(self.colors_spin.setValue)
        self.colors_spin.valueChanged.connect(self.colors_slider.setValue)
        grid.addWidget(colors_label, 0, 0)
        grid.addWidget(self.use_default_colors_cb, 0, 1)
        row1 = QHBoxLayout()
        row1.addWidget(low_lbl)
        row1.addWidget(self.colors_slider, 1)
        row1.addWidget(high_lbl)
        row1_w = QWidget()
        row1_w.setLayout(row1)
        grid.addWidget(row1_w, 1, 0, 1, 2)
        grid.addWidget(self.colors_spin, 1, 2)

        # Paths (%)
        self.use_default_paths_cb = QCheckBox("Use default")
        self.use_default_paths_cb.setChecked(True)
        self.use_default_paths_cb.toggled.connect(self._on_paths_default_toggled)
        paths_label = QLabel("Paths (%):")
        less_lbl = QLabel("Less")
        more_lbl = QLabel("More")
        self.paths_slider = QSlider(Qt.Orientation.Horizontal)
        self.paths_slider.setRange(1, 100)
        self.paths_slider.setValue(50)
        self.paths_slider.setEnabled(False)
        self.paths_spin = QSpinBox()
        self.paths_spin.setRange(1, 100)
        self.paths_spin.setValue(50)
        self.paths_spin.setSuffix("%")
        self.paths_spin.setEnabled(False)
        self.paths_slider.valueChanged.connect(self.paths_spin.setValue)
        self.paths_spin.valueChanged.connect(self.paths_slider.setValue)
        grid.addWidget(paths_label, 2, 0)
        grid.addWidget(self.use_default_paths_cb, 2, 1)
        row2 = QHBoxLayout()
        row2.addWidget(less_lbl)
        row2.addWidget(self.paths_slider, 1)
        row2.addWidget(more_lbl)
        row2_w = QWidget()
        row2_w.setLayout(row2)
        grid.addWidget(row2_w, 3, 0, 1, 2)
        grid.addWidget(self.paths_spin, 3, 2)

        # Transparency
        self.transparent_cb = QCheckBox("Make background transparent")
        self.transparent_cb.setChecked(True)
        grid.addWidget(self.transparent_cb, 4, 0, 1, 3)

        # Separator
        sep = QFrame()
        sep.setFrameShape(QFrame.Shape.HLine)
        sep.setFrameShadow(QFrame.Shadow.Sunken)
        grid.addWidget(sep, 5, 0, 1, 3)

        # Output size
        size_label = QLabel("Output Size:")
        grid.addWidget(size_label, 6, 0)
        size_row = QHBoxLayout()
        self.scale_radio = QRadioButton("Scale")
        self.exact_radio = QRadioButton("Exact size (px)")
        self.scale_radio.setChecked(True)
        size_row.addWidget(self.scale_radio)
        self.scale_spin = QDoubleSpinBox()
        self.scale_spin.setRange(0.01, 100.0)
        self.scale_spin.setSingleStep(0.05)
        self.scale_spin.setDecimals(2)
        self.scale_spin.setValue(1.0)
        size_row.addWidget(self.scale_spin)
        size_row.addSpacing(16)
        size_row.addWidget(self.exact_radio)
        self.width_spin = QSpinBox()
        self.width_spin.setRange(0, 100000)
        self.width_spin.setValue(0)
        self.width_spin.setSuffix(" w")
        self.width_spin.setEnabled(False)
        self.height_spin = QSpinBox()
        self.height_spin.setRange(0, 100000)
        self.height_spin.setValue(0)
        self.height_spin.setSuffix(" h")
        self.height_spin.setEnabled(False)
        size_row.addWidget(self.width_spin)
        size_row.addWidget(self.height_spin)
        size_w = QWidget()
        size_w.setLayout(size_row)
        grid.addWidget(size_w, 6, 1, 1, 2)

        # Toggle enablement between scale and exact size
        def _update_size_controls() -> None:
            exact = self.exact_radio.isChecked()
            self.width_spin.setEnabled(exact)
            self.height_spin.setEnabled(exact)
            self.scale_spin.setEnabled(not exact)
        self.scale_radio.toggled.connect(_update_size_controls)
        self.exact_radio.toggled.connect(_update_size_controls)
        _update_size_controls()

        return container

    def _on_colors_default_toggled(self, checked: bool) -> None:
        assert self.colors_slider is not None and self.colors_spin is not None
        self.colors_slider.setEnabled(not checked)
        self.colors_spin.setEnabled(not checked)

    def _on_paths_default_toggled(self, checked: bool) -> None:
        assert self.paths_slider is not None and self.paths_spin is not None
        self.paths_slider.setEnabled(not checked)
        self.paths_spin.setEnabled(not checked)

    def _restore_last_dirs(self) -> None:
        last_input = self.settings.value("last_input_dir", "", type=str)
        last_output = self.settings.value("last_output_dir", "", type=str)
        if last_input and os.path.isdir(last_input):
            self.input_edit.setText(last_input)
        if last_output and os.path.isdir(last_output):
            self.output_edit.setText(last_output)

    def _browse_input(self) -> None:
        start_dir = self.input_edit.text() or os.path.expanduser("~")
        directory = QFileDialog.getExistingDirectory(self, "Select input directory of PNGs", start_dir)
        if directory:
            self.input_edit.setText(directory)
            self.settings.setValue("last_input_dir", directory)

    def _browse_output(self) -> None:
        start_dir = self.output_edit.text() or os.path.expanduser("~")
        directory = QFileDialog.getExistingDirectory(self, "Select output directory", start_dir)
        if directory:
            self.output_edit.setText(directory)
            self.settings.setValue("last_output_dir", directory)

    def _append_log(self, text: str) -> None:
        self.log.appendPlainText(text.rstrip("\n"))
        self.log.verticalScrollBar().setValue(self.log.verticalScrollBar().maximum())

    def _set_ui_enabled(self, enabled: bool) -> None:
        self.run_button.setEnabled(enabled)

    def _run_conversion(self) -> None:
        input_dir = self.input_edit.text().strip()
        output_dir = self.output_edit.text().strip()

        if not input_dir:
            QMessageBox.warning(self, "Missing input", "Please choose an input directory.")
            return
        if not output_dir:
            QMessageBox.warning(self, "Missing output", "Please choose an output directory.")
            return
        if not os.path.isdir(input_dir):
            QMessageBox.critical(self, "Invalid input", "The selected input directory does not exist.")
            return
        if not os.path.isdir(output_dir):
            try:
                os.makedirs(output_dir, exist_ok=True)
            except Exception as exc:  # noqa: BLE001
                QMessageBox.critical(self, "Output error", f"Failed to create output directory: {exc}")
                return

        script_path = get_resource_path("convert_to_SVG.sh")
        if not script_path:
            QMessageBox.critical(self, "Script not found", "convert_to_SVG.sh was not found next to the app.")
            return

        self.log.clear()
        self._append_log("Starting conversion…")
        self._append_log(f"Input: {input_dir}")
        self._append_log(f"Output: {output_dir}")
        self._set_ui_enabled(False)

        self.process = QProcess(self)
        self.process.setProgram("/bin/bash")
        args = [script_path, input_dir]

        # Collect trace settings
        if self.transparent_cb is not None:
            args.extend(["--transparent", "true" if self.transparent_cb.isChecked() else "false"])
        if self.use_default_colors_cb is not None and self.colors_spin is not None:
            if not self.use_default_colors_cb.isChecked():
                args.extend(["--colors-pct", str(self.colors_spin.value())])
        if self.use_default_paths_cb is not None and self.paths_spin is not None:
            if not self.use_default_paths_cb.isChecked():
                args.extend(["--paths", str(self.paths_spin.value())])

        # Output sizing
        if self.exact_radio is not None and self.exact_radio.isChecked():
            # Pass only when specified (>0). Preserve aspect ratio in script.
            if self.width_spin is not None and self.width_spin.value() > 0:
                args.extend(["--out-w", str(self.width_spin.value())])
            if self.height_spin is not None and self.height_spin.value() > 0:
                args.extend(["--out-h", str(self.height_spin.value())])
        else:
            if self.scale_spin is not None and abs(self.scale_spin.value() - 1.0) > 1e-6:
                args.extend(["--scale", f"{self.scale_spin.value():.4f}"])

        self.process.setArguments(args)
        self.process.setWorkingDirectory(os.path.dirname(script_path))

        # Stream outputs
        self.process.readyReadStandardOutput.connect(
            lambda: self._append_log(bytes(self.process.readAllStandardOutput()).decode(errors="ignore"))
        )
        self.process.readyReadStandardError.connect(
            lambda: self._append_log(bytes(self.process.readAllStandardError()).decode(errors="ignore"))
        )
        self.process.finished.connect(lambda code, status: self._on_finished(code))

        # Start the process
        try:
            self.process.start()
        except Exception as exc:  # noqa: BLE001
            self._set_ui_enabled(True)
            QMessageBox.critical(self, "Failed to start", f"Could not run shell script: {exc}")

    def _on_finished(self, exit_code: int) -> None:
        self._append_log(f"Script finished with exit code {exit_code}")
        # After completion, attempt to move the generated SVG folder into the chosen output directory
        try:
            input_dir = self.input_edit.text().strip()
            output_dir = self.output_edit.text().strip()
            src_svg_dir = os.path.join(input_dir, "SVG")
            dest_svg_dir = os.path.join(output_dir, "SVG")

            if os.path.isdir(src_svg_dir):
                os.makedirs(dest_svg_dir, exist_ok=True)
                self._append_log(f"Copying results to: {dest_svg_dir}")
                self._merge_copy_tree(src_svg_dir, dest_svg_dir)
                # Clean up original folder after copy
                try:
                    shutil.rmtree(src_svg_dir)
                except Exception:
                    # Non-fatal if cleanup fails
                    pass
                if self.open_when_done.isChecked():
                    self._open_in_finder(dest_svg_dir)
                QMessageBox.information(self, "Done", "Conversion complete. Results copied to output directory.")
            else:
                QMessageBox.warning(
                    self,
                    "No SVG folder found",
                    "The script did not produce an 'SVG' folder in the input directory.",
                )
        finally:
            self._set_ui_enabled(True)
            self.process = None

    def _merge_copy_tree(self, src_dir: str, dst_dir: str) -> None:
        for root, dirs, files in os.walk(src_dir):
            rel = os.path.relpath(root, src_dir)
            target_root = os.path.join(dst_dir, rel) if rel != "." else dst_dir
            os.makedirs(target_root, exist_ok=True)
            for d in dirs:
                os.makedirs(os.path.join(target_root, d), exist_ok=True)
            for f in files:
                src_file = os.path.join(root, f)
                dst_file = os.path.join(target_root, f)
                try:
                    shutil.copy2(src_file, dst_file)
                except Exception as exc:  # noqa: BLE001
                    self._append_log(f"Failed to copy {src_file} -> {dst_file}: {exc}")

    def _open_in_finder(self, path: str) -> None:
        try:
            if sys.platform == "darwin":
                # macOS Finder
                QProcess.startDetached("/usr/bin/open", [path])
            elif sys.platform.startswith("win"):
                os.startfile(path)  # type: ignore[attr-defined]
            else:
                QProcess.startDetached("xdg-open", [path])
        except Exception:
            pass


def main() -> int:
    app = QApplication(sys.argv)
    w = SvgConverterApp()
    w.resize(720, 420)
    w.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())


