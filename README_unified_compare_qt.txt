Unified Comparison Tool (Qt)

Files included
- unified_compare_qt.py       -> the desktop Qt application
- unified_compare_app.py      -> the comparison engine
- requirements.txt            -> suggested Python packages

How to run
1. Create/activate your Python environment
2. Install dependencies:
   pip install -r requirements.txt
3. Start the app:
   python unified_compare_qt.py

Main usage
- Choose a source file
- Choose the target folder
- Choose the output folder
- Tick the comparison type: Email, PDF, Excel, Word, Text, TIFF, or All
- Click "Begin Comparison"

Outputs
- results.csv
- report.html

Notes
- TIFF OCR is optional and depends on Pillow + pytesseract, and a working Tesseract installation
- MSG parsing requires extract-msg
- DOCX parsing requires python-docx
- XLSX parsing requires openpyxl
- PDF parsing requires pypdf or PyPDF2
- Semantic similarity uses a local Ollama embeddings endpoint

Optional packaging
To build an EXE later with PyInstaller:
   pip install pyinstaller
   pyinstaller --noconsole --onefile unified_compare_qt.py
