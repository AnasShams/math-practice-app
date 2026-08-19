# Hybrid OCR Implementation - Complete Setup Guide

## ✅ What I've Done For You

1. Created backend Flask server (`app.py`) - handles OCR + OpenAI grading
2. Created `.env` file for backend configuration
3. Created `requirements.txt` with all Python dependencies
4. Updated Flutter app to call your backend instead of OpenAI directly
5. Updated Flutter `.env` to include backend URL

---

## 📋 Your Setup Checklist (Step-by-Step)

### **Step 1: Verify Python Installation**

Open PowerShell and run:

```powershell
python --version
pip --version
```

You should see Python 3.11+ and pip installed. If not, install Python first.

---

### **Step 2: Verify Tesseract OCR Installation**

- Download from: https://github.com/UB-Mannheim/tesseract/wiki
- Click: **tesseract-ocr-w64-setup-v5.x.exe** (Windows 64-bit)
- Run installer with default settings
- Verify installation:

```powershell
"C:\Program Files\Tesseract-OCR\tesseract.exe" --version
```

You should see version output.

---

### **Step 3: Activate Backend Environment & Install Dependencies**

Open PowerShell and run these commands:

```powershell
cd C:\Users\anass\Desktop\Anas\math_practice_backend
.\venv\Scripts\Activate
pip install -r requirements.txt
```

**Expected output:** All packages installed successfully

---

### **Step 4: Add OpenAI API Key to Backend**

Edit the `.env` file in `math_practice_backend` folder:

**File:** `C:\Users\anass\Desktop\Anas\math_practice_backend\.env`

Replace:

```
OPENAI_API_KEY=your_openai_api_key_here
```

With your actual key (copy from current Flutter `.env`):

```
OPENAI_API_KEY=your_openai_api_key_here
```

---

### **Step 5: Start the Backend Server**

In PowerShell (with venv activated):

```powershell
python app.py
```

**Expected output:**

```
WARNING in app.run(), this is a development server. Do not use it in production.
* Running on http://0.0.0.0:5000
```

**Keep this terminal open while testing!**

---

### **Step 6: Test Backend is Working**

Open a NEW PowerShell window and run:

```powershell
curl http://localhost:5000/health
```

**Expected output:**

```
{"status":"ok","message":"Backend is running"}
```

If you see this, your backend is working! ✅

---

### **Step 7: Test Flutter App**

In your Flutter project, rebuild the app:

```powershell
flutter clean
flutter pub get
flutter run
```

The app will now:

1. Accept handwritten input (same as before)
2. Send images to your local backend instead of OpenAI
3. Backend runs OCR to transcribe handwriting
4. Backend sends transcribed text to OpenAI for grading
5. You get feedback with less API cost

---

## 🔍 Architecture Summary

```
┌──────────────────────────┐
│   Flutter App on Phone   │
│  (or Android Emulator)   │
└────────────┬─────────────┘
             │ (Step images)
             ▼
┌──────────────────────────┐
│   Your Backend (Python)  │
│   - Tesseract OCR        │
│   - Image → Text         │
└────────────┬─────────────┘
             │ (Transcribed text)
             ▼
┌──────────────────────────┐
│   OpenAI API (GPT-4o)    │
│   - Grade solution       │
│   - Provide feedback     │
└────────────┬─────────────┘
             │ (Grading result)
             ▼
┌──────────────────────────┐
│   Student sees grading   │
│   + AI feedback          │
└──────────────────────────┘
```

---

## 🐛 Troubleshooting

### Issue: "Backend URL not configured"

**Solution:** Make sure your Flutter `.env` file has:

```
GRADING_API_URL=http://10.0.2.2:5000
```

### Issue: "Connection refused" or "Failed to connect"

**Solution:**

- Check backend is running: `curl http://localhost:5000/health`
- For Android Emulator: Use `http://10.0.2.2:5000` (special alias for host machine)
- For physical device: Use your PC's IP address instead (find with `ipconfig`)

### Issue: "Tesseract not found"

**Solution:** In `app.py`, update the path:

```python
pytesseract.pytesseract.pytesseract_cmd = r'C:\Program Files\Tesseract-OCR\tesseract.exe'
```

Make sure the path matches your installation location.

### Issue: "OPENAI_API_KEY not found in backend .env"

**Solution:**

- Edit `math_practice_backend\.env`
- Add your API key
- Restart backend server

---

## 💡 Cost Comparison

### Before (Direct OpenAI):

- Image → OpenAI Vision → Result
- Cost: ~$0.10 per submission (includes vision processing)

### After (Hybrid):

- Image → Local OCR → Text → OpenAI → Result
- Cost: ~$0.01 per submission (only text processing)
- **Savings: ~90% cheaper!**

---

## 📝 Optional: For Physical Android Device

If using a physical Android device instead of emulator:

1. Find your PC's IP address:

```powershell
ipconfig
```

Look for "IPv4 Address" (e.g., `192.168.1.100`)

2. Update Flutter `.env`:

```
GRADING_API_URL=http://192.168.1.100:5000
```

3. Make sure phone and PC are on same WiFi network

---

## Next Steps

Once this is working:

1. ✅ Test with handwritten math problems
2. 📊 Monitor OCR accuracy
3. 🚀 Consider deploying backend to cloud (Heroku, AWS, etc.)
4. 📈 Add progress tracking and analytics

**Questions?** Let me know if you get stuck!
