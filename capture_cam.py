import cv2
import os

def capture_and_save_image(filename="captured_image.jpg"):
    # Open the default camera (usually index 0)
    cap = cv2.VideoCapture(0)

    if not cap.isOpened():
        print("Error: Could not open video device.")
        return

    # Wait a moment for the camera to initialize
    import time
    time.sleep(2) 

    # Capture frame-by-frame
    ret, frame = cap.read()

    # Release the camera
    cap.release()

    if ret:
        # Save the captured frame
        cv2.imwrite(filename, frame)
        print(f"Image successfully saved as {filename}")
        # Optional: Display the image briefly before closing
        cv2.imshow("Captured Image", frame)
        cv2.waitKey(0) # Wait indefinitely until a key is pressed
        cv2.destroyAllWindows()
    else:
        print("Error: Could not capture image from camera.")

if __name__ == "__main__":
    # Note: This script requires the opencv-python library installed: pip install opencv-python
    capture_and_save_image()