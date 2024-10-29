# Snap&Nav: Smartphone-based Indoor Navigation System For Blind People via Floor Map Analysis and Intersection Detection
The repository contains the code that accompanies our MobileHCI 2024 paper [Snap&Nav: Smartphone-based Indoor Navigation System For Blind People via Floor Map Analysis and Intersection Detection](https://doi.org/10.1145/3676522).

![teaser](https://github.com/user-attachments/assets/dbe1df48-a386-402d-b3cc-85f1aa9248db)


## Abstract
We present Snap&Nav, a navigation system for blind people in unfamiliar buildings, without prebuilt digital maps. Instead, the system utilizes the floor map as its primary information source for route guidance. The system requires a sighted assistant to capture an image of the floor map, which is analyzed to create a node map containing intersections, destinations, and current positions on the floor. The system provides turn-by-turn navigation instructions while tracking users' positions on the node map by detecting intersections. Additionally, the system estimates the scale difference of the node map to provide distance information. Our system was validated through two user studies with 20 sighted and 12 blind participants. Results showed that sighted participants processed floor map images without being accustomed to the system, while blind participants navigated with increased confidence and lower cognitive load compared to the condition using only cane, appreciating the system's potential for use in various buildings.

## Python
Make sure to install the necessary dependencies before running the program. You can install them by using the `requirements.txt` file.
```
pip install -r requirements.txt
```

If you prefer using `conda`,
```
conda create -n snapnav python=3.12.7
conda activate snapnav
pip install -r requirements.txt
```

#### Sample Image Processing
- Place your input images in the `datasource` folder.
- To process the sample images, run the following command:
```
python3 main.py
```
#### Specifying Image Processing
- You can also specify a custom image to process by using the `--img` argument with the image file name. For example:
```
python3 main.py --img path_to_your_image.png
```

#### Outputs
- The program processes the input image and saves the result in JSON format inside the `outputs/json` folder.


## License
NEED TO WRITE

## ToDos
- [ ] Map Analysis module code release
- [ ] Navigation module code release
