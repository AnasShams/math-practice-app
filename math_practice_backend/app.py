"""
Math Practice Backend - Hybrid OCR + OpenAI Grading
Handles: OCR transcription + AI grading
"""

import os
import base64
import json
import re
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


def parse_division_equation(text):
    """Return lhs, divisor, quotient, and remainder for a simple division equation."""
    normalized = text.replace(',', '').replace('×', 'x').replace('X', 'x').replace('*', 'x')
    match = re.search(
        r'(?<!\d)(\d+)\s*=\s*(\d+)\s*x\s*(\d+)\s*\+\s*(\d+)(?!\d)',
        normalized,
    )
    if not match:
        return None
    return tuple(int(value) for value in match.groups())


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
        
        # Step 1: OCR - Convert images to text for debugging and fallback context
        transcribed_steps = []
        vision_steps = []
        for step in steps:
            step_number = step.get('stepNumber', 0)
            image_base64 = step.get('imageBase64', '')
            text_value = step.get('text', '').strip()

            if text_value:
                transcribed_steps.append({
                    'stepNumber': step_number,
                    'transcribedText': text_value,
                    'ocrError': None
                })
                vision_steps.append({
                    'stepNumber': step_number,
                    'text': text_value,
                    'imageUrl': None
                })
                continue
            
            if not image_base64:
                transcribed_steps.append({
                    'stepNumber': step_number,
                    'transcribedText': '(empty)',
                    'ocrError': None
                })
                vision_steps.append({
                    'stepNumber': step_number,
                    'text': '(empty)',
                    'imageUrl': None
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
                vision_steps.append({
                    'stepNumber': step_number,
                    'text': transcribed_text.strip(),
                    'imageUrl': f'data:image/png;base64,{image_base64}'
                })
            except Exception as e:
                transcribed_steps.append({
                    'stepNumber': step_number,
                    'transcribedText': '',
                    'ocrError': str(e)
                })
                vision_steps.append({
                    'stepNumber': step_number,
                    'text': '',
                    'imageUrl': f'data:image/png;base64,{image_base64}'
                })
        
        # Step 2: Send transcribed text to OpenAI for grading
        solution_text = "\n".join([
            f"Step {s['stepNumber']}: {s['transcribedText']}"
            for s in transcribed_steps
        ])
        
        vision_content = [
            {
                'type': 'text',
                'text': (
                    f"Question: {question_text}\n\n"
                    "Grade every submitted step in order and return exactly one result per step. "
                    "Inspect each handwriting image directly; OCR is only a hint and may be wrong. "
                    "Never call a step missing or empty when an equation is visibly present.\n\n"
                    "For an HCF question using Euclid's algorithm, apply this strict rubric:\n"
                    "1. Verify each equation numerically. A wrong product, quotient, or remainder is "
                    "a Calculation Error, even if the rest of the solution is correct.\n"
                    "2. Each next division must use the previous divisor and previous non-zero remainder. "
                    "If a required division is omitted, classify it as a Skipped Step.\n"
                    "3. The process ends only when the remainder is zero.\n"
                    "4. The HCF is the last non-zero remainder. A wrong conclusion is a Conceptual Error.\n"
                    "5. For each result, set correct=false for any error and set errorType to exactly one of "
                    "Calculation Error, Skipped Step, Conceptual Error, Dependent Error, or null. Explain the exact "
                    "problem in feedback, but never provide the corrected equation, final answer, or a "
                    "solution. Do not replace a specific error with a generic message about missing steps.\n\n"
                    f"OCR/text hints:\n{solution_text}"
                )
            }
        ]
        for step in vision_steps:
            if step['imageUrl']:
                vision_content.append({
                    'type': 'text',
                    'text': f"Image for submitted Step {step['stepNumber']}:"
                })
                vision_content.append({
                    'type': 'image_url',
                    'image_url': {'url': step['imageUrl']}
                })

        messages = [
            {
                'role': 'system',
                'content': (
                    "You are an expert Math Tutor. Grade the student's solution step by step. "
                    "The student has provided their solution in numbered steps, including images. "
                    "Output valid JSON with key 'steps' containing an array of objects with keys: "
                    "step (number), studentWork (string), correct (boolean), errorType (string or null), feedback (string). "
                    "Use exactly the errorType labels Calculation Error, Skipped Step, Conceptual Error, Dependent Error, or null. "
                    "Be encouraging but honest about mistakes. State only what is wrong; do not state the "
                    "correct answer or rewrite the step. A later step that depends on an earlier incorrect "
                    "step must be marked incorrect because the previous error invalidates it. "
                    "If an image is genuinely unreadable, say so instead of inventing a mistake."
                )
            },
            {
                'role': 'user',
                'content': vision_content
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
        grading_steps = grading_result.get('steps', [])

        # Arithmetic is deterministic; correct model mistakes for readable equations.
        for index, submitted_step in enumerate(transcribed_steps):
            equation = parse_division_equation(submitted_step['transcribedText'])
            if equation is None:
                continue

            lhs, divisor, quotient, remainder = equation
            if lhs == divisor * quotient + remainder:
                continue

            while len(grading_steps) <= index:
                grading_steps.append({})
            grading_steps[index] = {
                'step': submitted_step['stepNumber'],
                'studentWork': submitted_step['transcribedText'],
                'correct': False,
                'errorType': 'Calculation Error',
                'feedback': (
                    f'Calculation error: {divisor} x {quotient} + {remainder} does not equal {lhs}.'
                ),
            }

        # A later step cannot be correct when it depends on an earlier incorrect step.
        first_incorrect = next(
            (index for index, result in enumerate(grading_steps) if result.get('correct') is False),
            None,
        )
        if first_incorrect is not None:
            for index in range(first_incorrect + 1, min(len(grading_steps), len(transcribed_steps))):
                grading_steps[index] = {
                    **grading_steps[index],
                    'correct': False,
                    'errorType': 'Dependent Error',
                    'feedback': (
                        f'This step depends on Step {transcribed_steps[first_incorrect]["stepNumber"]}, '
                        'which contains an earlier error, so this result is also invalid.'
                    ),
                }

            first_result = grading_steps[first_incorrect]
            error_type = first_result.get('errorType')
            if error_type == 'Calculation Error':
                first_result['feedback'] = (
                    'This step contains a calculation error: the multiplication and addition in the equation '
                    'do not produce the number on the left side.'
                )
            elif error_type == 'Skipped Step':
                first_result['feedback'] = (
                    'This step skips a required part of the Euclidean algorithm, so the sequence is incomplete.'
                )
            elif error_type == 'Conceptual Error':
                first_result['feedback'] = (
                    'This conclusion is conceptually incorrect because it does not follow from the completed '
                    'Euclidean algorithm.'
                )
        
        return jsonify({
            'success': True,
            'steps': grading_steps,
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
