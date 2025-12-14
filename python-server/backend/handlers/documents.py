from ..config import DOCUMENTS_FOLDER
import os
import cv2
import numpy as np
import logging

logger = logging.getLogger(__name__)

def select(results, img=None):
    """
    Detect documents by analyzing:
    - Filename keywords (doc, receipt, invoice, paper, screenshot)
    - Image characteristics: high contrast, white/light background, text-like edges
    """
    # Check filename first
    try:
        src = getattr(results, 'orig_img_path', None) or getattr(results, 'path', None)
    except Exception:
        src = None

    if not src and isinstance(results, str):
        src = results

    if src:
        name = os.path.basename(src).lower()
        for kw in ('doc', 'receipt', 'invoice', 'paper', 'scan'):
            if kw in name:
                return DOCUMENTS_FOLDER

    # Analyze image if provided
    if img is not None:
        try:
            # Convert to grayscale
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY) if len(img.shape) == 3 else img
            h, w = gray.shape
            
            # STRICT CHECK 1: Very bright overall (documents are usually white/light background)
            mean_brightness = np.mean(gray)
            if mean_brightness < 220:  # Much stricter - must be very bright
                return None
            
            # STRICT CHECK 2: High percentage of very bright pixels (white background)
            bright_pixels = np.sum(gray > 240) / gray.size
            if bright_pixels < 0.5:  # At least 50% very bright pixels
                return None
            
            # STRICT CHECK 3: Color saturation - documents are low saturation (near-grayscale)
            if len(img.shape) == 3:
                hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
                saturation = hsv[:, :, 1]
                mean_saturation = np.mean(saturation)
                if mean_saturation > 40:  # Documents are typically desaturated
                    return None
            
            # STRICT CHECK 4: Text creates specific contrast patterns
            std_dev = np.std(gray)
            if std_dev < 30 or std_dev > 70:  # Text has moderate, consistent contrast
                return None
            
            # STRICT CHECK 5: Edge detection for text patterns
            edges = cv2.Canny(gray, 100, 200)  # Higher thresholds for cleaner text edges
            edge_density = np.sum(edges > 0) / edges.size
            
            # Documents have specific edge density from text (narrow range)
            if not (0.05 < edge_density < 0.15):
                return None
            
            # STRICT CHECK 6: Horizontal text line detection
            horizontal_edges = cv2.Sobel(gray, cv2.CV_64F, 0, 1, ksize=3)
            h_edge_strength = np.mean(np.abs(horizontal_edges))
            
            # Must have strong horizontal patterns from text lines
            if h_edge_strength < 25:
                return None
            
            # STRICT CHECK 7: Detect horizontal lines (common in documents - underlines, tables)
            lines = cv2.HoughLinesP(edges, 1, np.pi/180, threshold=100, minLineLength=w//4, maxLineGap=10)
            if lines is not None:
                horizontal_lines = 0
                for line in lines:
                    x1, y1, x2, y2 = line[0]
                    angle = abs(np.arctan2(y2 - y1, x2 - x1) * 180 / np.pi)
                    if angle < 10 or angle > 170:  # Nearly horizontal
                        horizontal_lines += 1
                # Documents typically have multiple horizontal lines
                if horizontal_lines < 2:
                    return None
            else:
                return None  # No lines detected at all
            
            # STRICT CHECK 8: Aspect ratio - documents are typically portrait or standard paper
            aspect_ratio = w / h
            if not (0.5 < aspect_ratio < 1.5):  # Exclude very wide/tall images
                return None
            
            # ALL checks passed - this is likely a document
            return DOCUMENTS_FOLDER
                
        except Exception as e:
            logger.error(f"Document detection error: {e}")
            pass

    return None
