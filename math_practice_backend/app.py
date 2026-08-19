"""
Math Practice Backend - Hybrid OCR + OpenAI Grading
Handles: OCR transcription + AI grading
"""

import os
import base64
import json
from io import BytesIO
from flask import Flask, request, jsonify
from flask_cors import CORS
import cv2
import numpy as np
import pytesseract
from openai import OpenAI
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Initialize Flask app
app = Flask(__name__)
CORS(app)  # Enable CORS for Flutter requests

# Initialize OpenAI client
openai_client = OpenAI(api_key=os.getenv('OPENAI_API_KEY'))

# Configure Tesseract path (Windows)
# Adjust this path if you installed Tesseract to a different location
pytesseract.pytesseract.pytesseract_cmd = r'C:\Program Files\Tesseract-OCR\tesseract.exe'


@app.route('/health', methods=['GET'])
def health_check():
    """Simple health check endpoint"""
    return jsonify({'status': 'ok', 'message': 'Backend is running'}), 200


@app.route('/grade', methods=['POST'])
def grade_solution():
    """
    Main grading endpoint
    
    Expected JSON payload:
    {
        "questionId": 1,
        "questionText": "Solve 2x + 5 = 13",
        "steps": [
            {
                "stepNumber": 1,
                "imageBase64": "data:image/png;base64,iVBORw0KGgo..."
            },
            ...
        ]
    }
    
    Returns:
    {
        "success": true,
        "steps": [
            {
                "step": 1,
                "studentWork": "transcribed text from OCR",
                "correct": true/false,
                "errorType": "type of error or null",
                "feedback": "AI feedback"
            },
            ...
        ]
    }
    """
    try:
        data = request.get_json()
        
        if not data or 'steps' not in data:
            return jsonify({'success': False, 'error': 'Missing steps in request'}), 400
        
        question_text = data.get('questionText', 'Unknown question')
        steps = data.get('steps', [])
        
        if not steps:
            return jsonify({'success': False, 'error': 'No steps provided'}), 400
        
        # Step 1: OCR - Convert images to text
        transcribed_steps = []
        for step in steps:
            step_number = step.get('stepNumber', 0)
            image_base64 = step.get('imageBase64', '')
            
            if not image_base64:
                transcribed_steps.append({
                    'stepNumber': step_number,
                    'transcribedText': '(empty)',
                    'ocrError': None
                })
                continue
            
            try:
                # Remove data URL prefix if present
                if image_base64.startswith('data:image/'):
                    image_base64 = image_base64.split(',')[1]
                
                # Decode base64 to image bytes
                image_data = base64.b64decode(image_base64)
                nparr = np.frombuffer(image_data, np.uint8)
                image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
                
                if image is None:
                    raise Exception("Could not decode image")
                
                # Run OCR
                transcribed_text = pytesseract.image_to_string(image)
                
                transcribed_steps.append({
                    'stepNumber': step_number,
                    'transcribedText': transcribed_text.strip(),
                    'ocrError': None
                })
            except Exception as e:
                transcribed_steps.append({
                    'stepNumber': step_number,
                    'transcribedText': '',
                    'ocrError': str(e)
                })
        
        # Step 2: Send transcribed text to OpenAI for grading
        solution_text = "\n".join([
            f"Step {s['stepNumber']}: {s['transcribedText']}"
            for s in transcribed_steps
        ])
        
        messages = [
            {
                'role': 'system',
                'content': (
                    "You are an expert Math Tutor. Grade the student's solution step by step. "
                    "The student has provided their solution in numbered steps. "
                    "Output valid JSON with key 'steps' containing an array of objects with keys: "
                    "step (number), studentWork (string), correct (boolean), errorType (string or null), feedback (string). "
                    "Be encouraging but honest about mistakes. Provide specific guidance on how to improve."
                )
            },
            {
                'role': 'user',
                'content': f"Question: {question_text}\n\nStudent Solution:\n{solution_text}"
            }
        ]
        
        # Call OpenAI API
        response = openai_client.chat.completions.create(
            model='gpt-4o',
            messages=messages,
            temperature=0.2,
            response_format={'type': 'json_object'}
        )
        
        # Parse OpenAI response
        content = response.choices[0].message.content
        grading_result = json.loads(content)
        
        return jsonify({
            'success': True,
            'steps': grading_result.get('steps', []),
            'ocrDebug': transcribed_steps  # Include OCR results for debugging
        }), 200
        
    except json.JSONDecodeError:
        return jsonify({'success': False, 'error': 'Invalid JSON from OpenAI response'}), 500
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


@app.route('/ocr-only', methods=['POST'])
def ocr_only():
    """
    Optional: OCR-only endpoint (for debugging or if you just want transcription)
    
    Request:
    {
        "imageBase64": "data:image/png;base64,..."
    }
    
    Response:
    {
        "success": true,
        "transcribedText": "the extracted text"
    }
    """
    try:
        data = request.get_json()
        image_base64 = data.get('imageBase64', '')
        
        if not image_base64:
            return jsonify({'success': False, 'error': 'No image provided'}), 400
        
        # Remove data URL prefix
        if image_base64.startswith('data:image/'):
            image_base64 = image_base64.split(',')[1]
        
        # Decode and process
        image_data = base64.b64decode(image_base64)
        nparr = np.frombuffer(image_data, np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if image is None:
            return jsonify({'success': False, 'error': 'Could not decode image'}), 400
        
        transcribed_text = pytesseract.image_to_string(image)
        
        return jsonify({
            'success': True,
            'transcribedText': transcribed_text.strip()
        }), 200
        
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 500


if __name__ == '__main__':
    # Development server
    # For production, use gunicorn: gunicorn app:app --bind 0.0.0.0:5000
    app.run(debug=True, host='0.0.0.0', port=5000)
