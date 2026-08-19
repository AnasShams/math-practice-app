# Quick Start Checklist

## BEFORE YOU START

- [ ] Python 3.11+ installed (check with `python --version`)
- [ ] Tesseract OCR installed (C:\Program Files\Tesseract-OCR\tesseract.exe)
- [ ] Flask backend folder created at C:\Users\anass\Desktop\Anas\math_practice_backend

---

## PART 1: Python Setup (First Time Only)

```powershell
cd C:\Users\anass\Desktop\Anas\math_practice_backend
python -m venv venv
.\venv\Scripts\Activate
pip install -r requirements.txt
```

Wait for all packages to install. ⏱️

---

## PART 2: Configure Backend (One Time)

Open `.env` in math_practice_backend folder:

```
OPENAI_API_KEY=your_openai_api_key_here
FLASK_ENV=development
FLASK_DEBUG=True
```

---

## PART 3: Start Backend (Every Time You Test)

```powershell
cd C:\Users\anass\Desktop\Anas\math_practice_backend
.\venv\Scripts\Activate
python app.py
```

✅ When you see "Running on http://0.0.0.0:5000" - backend is ready!

**Keep this terminal window OPEN**

---

## PART 4: Start Flutter App (In New Terminal)

```powershell
cd C:\Users\anass\Desktop\Anas\math_practice_flutter
flutter run
```

---

## PART 5: Test It Out

1. Open app on emulator/device
2. Write a math problem by hand
3. Click "Check Answer"
4. Wait ~5-10 seconds
5. See grading + AI feedback

---

## COMMON ISSUES & FIXES

**"Backend URL not configured"**
→ Check Flutter `.env` has `GRADING_API_URL=http://10.0.2.2:5000`

**"Connection refused"**
→ Make sure backend is running (check terminal with `python app.py`)

**"ModuleNotFoundError: No module named 'pytesseract'"**
→ Run `pip install -r requirements.txt` while venv is activated

**"Tesseract not found"**
→ Install Tesseract from: https://github.com/UB-Mannheim/tesseract/wiki
→ Or update path in `app.py` line 14

---

## THAT'S IT! 🎉

You now have:

- ✅ Local OCR (Tesseract)
- ✅ AI Grading (OpenAI)
- ✅ 90% cheaper API costs
- ✅ Faster processing
