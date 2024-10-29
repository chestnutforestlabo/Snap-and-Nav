import cv2
import argparse
from shapely.geometry import Polygon
import easyocr


class OCR:
    def __init__(self, image):
        self.image = image
        self.height = 480
        self.width = 640

    def ocrfunc(self):
        reader = easyocr.Reader(['ja','en'])
        gray = cv2.cvtColor(self.image, cv2.COLOR_BGR2GRAY)

        ocr_result = reader.readtext(gray)
        self.ocr_result = ocr_result
        
        return ocr_result

    def apply_ocr_with_bounding_boxes(self):
        bounding_boxes = []
        text_box = []

        merger = OCR(self.image)

        for detection in self.ocr_result:
            top_left = tuple(map(int, detection[0][0]))
            bottom_right = tuple(map(int, detection[0][2]))
            text = detection[1]

            resized_top_left = (int(top_left[0] * (self.width / self.image.shape[1])),
                                int(top_left[1] * (self.height / self.image.shape[0])))
            resized_bottom_right = (int(bottom_right[0] * (self.width / self.image.shape[1])),
                                    int(bottom_right[1] * (self.height / self.image.shape[0])))

            is_merged = False
            for i, (box, merged_text) in enumerate(zip(bounding_boxes, text_box)):
                # if bounding box is overlapped, merge it and text.
                if merger.is_overlap(resized_top_left, resized_bottom_right, box[0], box[1]):
                    merged_box = merger.merge_boxes(resized_top_left, resized_bottom_right, box[0], box[1])
                    bounding_boxes[i] = merged_box

                    merged_text += ' ' + text
                    text_box[i] = merged_text
                    is_merged = True
                    break
            # if not, add it.
            if not is_merged:
                bounding_boxes.append((resized_top_left, resized_bottom_right))
                text_box.append(text)

        return bounding_boxes, text_box

    @staticmethod
    def is_overlap(top_left1, bottom_right1, top_left2, bottom_right2):
        poly1 = Polygon([top_left1, (bottom_right1[0], top_left1[1]), bottom_right1, (top_left1[0], bottom_right1[1])])
        poly2 = Polygon([top_left2, (bottom_right2[0], top_left2[1]), bottom_right2, (top_left2[0], bottom_right2[1])])
        return poly1.intersects(poly2)

    @staticmethod
    def merge_boxes(top_left1, bottom_right1, top_left2, bottom_right2):
        min_x = min(top_left1[0], top_left2[0])
        min_y = min(top_left1[1], top_left2[1])
        max_x = max(bottom_right1[0], bottom_right2[0])
        max_y = max(bottom_right1[1], bottom_right2[1])
        return ((min_x, min_y), (max_x, max_y))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Apply OCR to an image and find bounding boxes.")
    parser.add_argument('--img', required=True, help='Path to the input image file.')

    args = parser.parse_args()

    image = cv2.imread(args.img)
    if image is None:
        print(f"Error: Could not read image from {args.img}")
        exit(1)

    reader = easyocr.Reader(['ja', 'en'])
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    ocr_result = reader.readtext(gray)

    ocr_merger = OCR(image, ocr_result)
    bounding_boxes, text_box = ocr_merger.apply_ocr_with_bounding_boxes()

    for i, (box, text) in enumerate(zip(bounding_boxes, text_box)):
        print(f"Bounding Box {i}: {box}, Text: {text}")