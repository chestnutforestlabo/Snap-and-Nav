import numpy as np
import matplotlib.pyplot as plt
import time
import cv2
import easyocr

def theta_calc(a, b, c):
    a = np.array(a)
    b = np.array(b)
    c = np.array(c)

    vec_a = a - b
    vec_c = c - b

    length_vec_a = np.linalg.norm(vec_a)
    length_vec_c = np.linalg.norm(vec_c)
    inner_product = np.inner(vec_a, vec_c)
    cos = inner_product / (length_vec_a * length_vec_c)

    rad = np.arccos(cos)
    degree = np.rad2deg(rad)

    return degree

def figure_nodemap(nodes, path):
    plt.figure()
    plt.axis('equal')
    for index, x,y,connect in nodes:  
        plt.plot(x, -y, 'ro')
        plt.annotate(str(index), (x, -y), textcoords="offset points", xytext=(0, 10), ha='center')

        #connect two intersection
        for connect_index in connect:
            for tmp in nodes:
                target = None
                if tmp[0] == connect_index:
                    target = tmp
                    break

            connected_x = target[1]
            connected_y = target[2]
            rotated_connected_coords = (connected_x, -connected_y) 
            plt.plot([x, rotated_connected_coords[0]], [-y, rotated_connected_coords[1]], 'b-')

    plt.savefig(path)

def timer_decorator(func):
    def wrapper(*args, **kwargs):
        start = time.perf_counter()
        result = func(*args, **kwargs)
        end = time.perf_counter()
        print(f'Function {func.__name__} took {end - start} seconds to run.')
        return result
    return wrapper