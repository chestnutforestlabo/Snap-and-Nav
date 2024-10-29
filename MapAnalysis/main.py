import cv2
import numpy as np
import argparse
import os
import json
import matplotlib
import yaml
from skimage import morphology
from skimage import io, measure, color
from scipy.spatial.distance import cdist
import matplotlib.pyplot as plt
from concurrent.futures import ThreadPoolExecutor
matplotlib.use('Agg')

from ocr import OCR
from util import theta_calc, figure_nodemap, timer_decorator


class MapRecognizer:

    def __init__(self,save_path) -> None:
        self.save_path = save_path
        self.img_path = os.path.join(self.save_path,'process_img')
        self.json_path = os.path.join(self.save_path,'json')

        if not os.path.exists(self.save_path):
            os.makedirs(self.save_path)

        if not os.path.exists(self.img_path):
            os.makedirs(self.img_path)

        if not os.path.exists(self.json_path):
            os.makedirs(self.json_path)

        with open("config.yml", "r") as ymlfile:
            self.config = yaml.safe_load(ymlfile)

    def recognize_map(self, image_path):
        floormap_image = cv2.imread(image_path)
        basename = os.path.basename(image_path)
        name_without_extension = basename.split(".")[0]
        self.input_image_path_img = os.path.join(self.img_path,name_without_extension)
        if not os.path.exists(self.input_image_path_img):
            os.makedirs(self.input_image_path_img)

        self.input_image_path_json = os.path.join(self.json_path,name_without_extension)
        if not os.path.exists(self.input_image_path_json):
            os.makedirs(self.input_image_path_json)
        
        @timer_decorator
        def thread1():
            print("THREAD1 START")
            self.getpath(floormap_image)
            labeled_image = self.extract_conrridor(floormap_image)
            skeleton_image = self.skeletonize(floormap_image)
            intersections = self.extract_corner(skeleton_image)
            nodes = self.extract_connection(floormap_image, intersections, skeleton_image)
            print("THREAD1 END")
            return nodes, labeled_image
        
        @timer_decorator
        def thread2():
            print("THREAD2 START")
            ocr_merger = OCR(floormap_image)
            ocr = ocr_merger.ocrfunc()
            bounding_boxes = ocr_merger.apply_ocr_with_bounding_boxes()
            print("THREAD2 END")
            return bounding_boxes

        executor = ThreadPoolExecutor(max_workers=2)
        future1 = executor.submit(thread1)
        future2 = executor.submit(thread2)
        nodes, labeled_image = future1.result()
        bounding_boxes = future2.result()

        pois = self.extract_pois(floormap_image, labeled_image, bounding_boxes)
        executor.shutdown()
        self.write_to_json(nodes, pois)

        plt.close()


    @timer_decorator
    def getpath(self, floormap_image):
            params = self.config["getpath_parameters"]

            lower_red = np.array(params["lower_red"])
            upper_red = np.array(params["upper_red"])
            binary_lower_threshold = params["binary_lower_threshold"]
            binary_upper_threshold = params["binary_upper_threshold"]
            kernel_size = params["kernel_size"]
            kernel = np.ones((kernel_size, kernel_size), np.uint8)
            CC_connectivity = params["CC_connectivity"]
            dilated_iteration = params["dilated_iteration"]

            mask = cv2.inRange(floormap_image, lower_red, upper_red)
            floormap_image[mask > 0] = [255, 255, 255]

            grayscale = cv2.cvtColor(floormap_image, cv2.COLOR_BGR2GRAY)
            dilated_image = cv2.dilate(grayscale, kernel, iterations=dilated_iteration)
            _, binary_image = cv2.threshold(dilated_image, binary_lower_threshold, binary_upper_threshold, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)

            _, labels, stats, _ = cv2.connectedComponentsWithStats(binary_image, connectivity=CC_connectivity)
            largest_area_index = np.argmax(stats[1:, cv2.CC_STAT_AREA]) + 1
            largest_area_mask = np.uint8(labels == largest_area_index) * 255

            result_mask = np.zeros_like(binary_image)
            result_mask[largest_area_mask > 0] = 255

            cv2.imwrite(os.path.join(self.input_image_path_img,'path_image.png'), result_mask)

    @timer_decorator
    def extract_conrridor(self, floormap_image):
        params = self.config["extract_corridor_parameters"]

        canny_lower = params["canny_lower"]
        canny_upper = params["canny_upper"]
        kernel_size = params["kernel_size"]
        kernel = np.ones((kernel_size, kernel_size), np.uint8)
        canny_2_lower = params["canny_2_lower"]
        canny_2_upper = params["canny_2_upper"]
        dilation_iteration = params["dilation_iteration"]
        erosion_iteration = params["erosion_iteration"]
        area_threshold = params["area_threshold"]
        addWeighted_alpha = params["addWeighted_alpha"]
        binary_threshold = params["binary_threshold"]
        area_threshold_2 = params["area_threshold_2"]
        measure_connectivity = params["measure_connectivity"]

        gray = cv2.cvtColor(floormap_image, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        edges = cv2.Canny(blurred, canny_lower, canny_upper)
        contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        mask = np.zeros_like(edges)
        for contour in contours:
            cv2.drawContours(mask, [contour], 0, (255), -1)

        masked_image = cv2.bitwise_and(floormap_image, floormap_image, mask=mask)
        edges = cv2.Canny(masked_image, canny_2_lower, canny_2_upper)

        dilation = cv2.dilate(edges, kernel, iterations=dilation_iteration)
        erosion = cv2.erode(edges, kernel, iterations=erosion_iteration)

        height, width, _ = floormap_image.shape
        image2_resized = cv2.resize(erosion, (width, height))

        blended = cv2.addWeighted(dilation, addWeighted_alpha, image2_resized, 1-addWeighted_alpha, 0)
        closing = cv2.morphologyEx(blended, cv2.MORPH_CLOSE, kernel)
        _, binary = cv2.threshold(closing, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)

        num_labels, labels, stats, _ = cv2.connectedComponentsWithStats(binary)

        floor_binary = np.zeros_like(floormap_image)
        for label in range(1, num_labels):
            area = stats[label, cv2.CC_STAT_AREA]
            if area > area_threshold:
                floor_binary[labels == label] = [255, 255, 255]

        gray = cv2.cvtColor(floor_binary, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        edges = cv2.Canny(blurred, canny_lower, canny_upper)
        contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        mask = np.zeros_like(edges)
        for contour in contours:
            cv2.drawContours(mask, [contour], 0, (255), -1)

        merged_image = cv2.bitwise_and(gray, mask)
        binary_image = merged_image > binary_threshold
        labeled_image, num_labels = measure.label(binary_image, connectivity=measure_connectivity, return_num=True)
        properties = measure.regionprops(labeled_image)

        filtered_properties = [prop for prop in properties if prop.area > area_threshold_2]
        filtered_properties.sort(key=lambda prop: prop.area, reverse=True)
        largest_region = filtered_properties[0]

        filtered_labeled_image = np.zeros_like(labeled_image)
        filtered_labeled_image[labeled_image == largest_region.label] = labeled_image[labeled_image == largest_region.label]

        binary_image = merged_image > binary_threshold
        labeled_image, num_labels = measure.label(binary_image, connectivity=measure_connectivity, return_num=True)

        return labeled_image


    @timer_decorator
    def skeletonize(self, path_image):
        params = self.config["skeletonize_parameters"]

        scaler = params["scaler"]
        kernel1_size = params["kernel1_size"]
        kernel2_size = params["kernel2_size"]
        kernel1 = np.ones((kernel1_size, kernel1_size), np.uint8)
        kernel2 = np.ones((kernel2_size, kernel2_size), np.uint8)
        dilate_iteration = params["dilate_iteration"]
        erode_iteration = params["erode_iteration"]

        original_image = cv2.imread(os.path.join(self.input_image_path_img,'path_image.png'))

        original_height = original_image.shape[0]
        original_width = original_image.shape[1]

        target_width = original_width // scaler
        target_height = original_height // scaler

        resized_image = cv2.resize(original_image, (target_width, target_height))

        dilated_image = cv2.dilate(resized_image, kernel2, iterations=dilate_iteration)
        eroded_image = cv2.erode(dilated_image, kernel1, iterations = erode_iteration)

        skeleton = morphology.skeletonize(eroded_image)
        skeleton_uint8 = (skeleton * 255).astype('uint8') 

        cv2.imwrite(os.path.join(self.input_image_path_img,'skeleton.png'),skeleton_uint8)

    @timer_decorator
    def extract_corner(self, skeleton):
        params = self.config["extract_corner_parameters"]

        block_size = params["block_size"]
        ksize = params["ksize"]  
        k = params["k"]

        map_recognizer = MapRecognizer("outputs")

        binary_image = cv2.imread(os.path.join(self.input_image_path_img,'skeleton.png'), cv2.IMREAD_GRAYSCALE)
        harris_corners = cv2.cornerHarris(binary_image, block_size, ksize, k)

        threshold = 0.01 * harris_corners.max()
        corner_image = np.zeros_like(binary_image)
        corner_image[harris_corners > threshold] = 255

        corner_image = cv2.dilate(corner_image, None)
        result_images = cv2.cvtColor(binary_image, cv2.COLOR_GRAY2BGR)
        result_images[corner_image == 255] = [0, 0, 255]  # highlight the corners

        # coordinate of corners
        corners = np.argwhere(corner_image == 255)
        skeleton = cv2.imread(os.path.join(self.input_image_path_img,'skeleton.png'))

        intersections = map_recognizer.delete_node(corners, skeleton, binary_image)

        return intersections


    def count_outgoing_lines(self, image, point):
        dx = [1, 1, 1, 0, 0, -1, -1, -1]
        dy = [1, 0, -1, 1, -1, 1, 0, -1]
        count_outgoing_directions = 0

        for i in range(len(dx)):
            x = point[0] + dx[i]
            y = point[1] + dy[i]

            if image[x, y] != 0:
                count_outgoing_directions += 1

        return count_outgoing_directions

    def delete_node(self, corners, skeleton, binary_image):
        params = self.config["delete_node_parameters"]

        min_distance = params["min_distance"]
        delete_indices1 = []  #delete corner list
        delete_indices2 = []

        #if the corner does not exist on the skeleton, delete it.
        for i, point in enumerate(corners):
            if all(skeleton[point[0], point[1]] != 255):
                delete_indices2.append(i)
        corners = np.delete(corners, delete_indices2, axis=0)

        for i in range(len(corners)):
            for j in range(i+1, len(corners)):
                distance = np.linalg.norm(corners[i] - corners[j])
                if distance < min_distance:
                    if j not in delete_indices1:
                        cnt_i = self.count_outgoing_lines(binary_image, corners[i])
                        cnt_j = self.count_outgoing_lines(binary_image, corners[j])
                        if cnt_i < cnt_j:
                            delete_indices1.append(i)
                        else:
                            delete_indices1.append(j)

        intersections = np.delete(corners, delete_indices1, axis=0)
        return intersections


    @timer_decorator
    def extract_connection(self, floormap_image, intersections, skeleton_image):
        params = self.config["extract_connection_parameters"]

        threshold_value = params["threshold_value"]
        theta = params["theta"]
        threshold_node_theta = params["threshold_node_theta"]
        min_node_distance = params["min_node_distance"]

        skeleton_image = cv2.imread(os.path.join(self.input_image_path_img,'skeleton.png'), cv2.IMREAD_GRAYSCALE)
        _, binary_image = cv2.threshold(skeleton_image, threshold_value, 255, cv2.THRESH_BINARY)

        connections = []
        connections_dict = {}

        self.find_connections(intersections, binary_image, connections)

        ar_corners = np.array(intersections)

        for connection in connections:
            point_index, _, coords = connection
            closest_point_index = np.argmin(np.linalg.norm(ar_corners - coords, axis=1))
            if point_index not in connections_dict:
                connections_dict[point_index] = []
            connections_dict[point_index].append(closest_point_index)

        delete_node_corridor = {}
        delete_node_near = {}

        for point_index, connected_points in connections_dict.items():
            point_coords = ar_corners[point_index]
            rotated_coords = (point_coords[1], -point_coords[0])  
            if len(connected_points) == 2:
                theta = theta_calc(ar_corners[connected_points[0]], ar_corners[point_index], ar_corners[connected_points[1]])
                if theta > threshold_node_theta:
                    delete_node_corridor[point_index] = []
                    delete_node_corridor[point_index].append(connected_points)

            if len(connected_points) == 1:
                distance = np.linalg.norm(ar_corners[point_index] - ar_corners[connected_points[0]])
                if distance < min_node_distance:
                    delete_node_near[point_index] = []
                    delete_node_near[point_index].append(connected_points)
                
        #if sentence is for error
        for point_index, connected_points in delete_node_corridor.items():
            if connected_points[0][0] not in connections_dict:
                connections_dict[connected_points[0][1]] = []
            connections_dict[connected_points[0][0]].append(connected_points[0][1])
            if point_index in connections_dict[connected_points[0][0]]:
                connections_dict[connected_points[0][0]].remove(point_index)
            
            if connected_points[0][1] not in connections_dict:
                connections_dict[connected_points[0][1]] = []
            connections_dict[connected_points[0][1]].append(connected_points[0][0])
            if point_index in connections_dict[connected_points[0][1]]:
                connections_dict[connected_points[0][1]].remove(point_index)
            del connections_dict[point_index]

        for point_index, connected_points in delete_node_near.items():
            if point_index in connections_dict[connected_points[0][0]]:
                connections_dict[connected_points[0][0]].remove(point_index)
            del connections_dict[point_index]

        nodes = [] #nodes for intersection list

        for point_index, connected_points in connections_dict.items():
            point_coords = ar_corners[point_index]
            rotated_coords = (point_coords[1], point_coords[0])  

            resized_coords_x = int(rotated_coords[0]*(floormap_image.shape[1] / skeleton_image.shape[1]))
            resized_coords_y = int(rotated_coords[1]*(floormap_image.shape[0] / skeleton_image.shape[0]))

            nodes.append((point_index, resized_coords_x, resized_coords_y, connected_points))

        for node in nodes:
            index, _, _, connect = node
            for point in connect:              
                target = None
                tmp_flag = False
                for node_2 in nodes:
                    if node_2[0] == point:
                        target = node_2
                        tmp_flag = True
                        break
                if tmp_flag == False:
                    connect.remove(point)
                else:
                    if index not in target[3]:
                        target[3].append(index)
        
        #figure_nodemap(nodes, path=os.path.join(self.input_image_path_img,'nodemap.png'))
        return nodes

    def find_endpoint(self, i, x, y,  start, binary_image, visited, intersections, connections):
        params = self.config["find_endpoint_parameters"]

        current_x = x
        current_y = y
        tmp_x = x
        tmp_y = y
        is_find_connection = False
        explore_distance = 0
        tmp_corners = np.array(intersections)
        max_explore_distance = params["max_explore_distance"]

        while is_find_connection == False:
            is_updated = False
            explore_distance = explore_distance + 1
            for dx in [-1, 0, 1]:
                for dy in [-1, 0, 1]:
                    if dx == 0 and dy == 0:
                        continue
                    if visited[current_y + dy, current_x + dx]:
                        if dx == 1 and dy == 1:  #explore all directions
                            is_find_connection = True
                            is_updated = True
                        continue

                    tmp_x = current_x + dx
                    tmp_y = current_y + dy
                    visited[tmp_y, tmp_x] = True

                    #if on the skeleton, update the location
                    if binary_image[tmp_y, tmp_x]:
                        current_x = tmp_x
                        current_y = tmp_y
                        is_updated = True

                        # if find connection point, 
                        if any((abs(elem[0] - current_y) < 5 and abs(elem[1] - current_x) < 5) for elem in tmp_corners):
                            if abs(current_x - start[1]) + abs(current_y - start[0]) > 10:
                                connections.append((i, start[0],[current_y,current_x]))
                                is_find_connection = True

                    if is_updated:
                        break
                    if is_updated == False and dx == 1 and dy == 1:
                        is_find_connection = True
                        is_updated = True
                        break
                    if explore_distance > max_explore_distance:
                        is_find_connection = True
                        is_updated = True
                        break
                if is_updated:
                    break


    def find_connections(self, intersections, binary_image, connections):

        for i in range(len(intersections)):
            start_point = intersections[i]
            current_point = intersections[i]
            visited = np.zeros((binary_image.shape[0], binary_image.shape[1]), dtype=bool)
            visited[start_point[0], start_point[1]] = True

            for dx in [-1, 0, 1]:
                for dy in [-1, 0, 1]:
                    if dx == 0 and dy == 0:
                        continue

                    x = current_point[1] + dx
                    y = current_point[0] + dy
                    visited[y,x] = True

                    if 1 < x < binary_image.shape[1] - 1 and 1 < y < binary_image.shape[0] - 1:
                        if binary_image[y, x]:
                            self.find_endpoint(i, x, y, start_point, binary_image, visited, intersections, connections)


    @timer_decorator
    def extract_pois(self, floormap_image, labeled_image, bounding_boxes):
        params = self.config["extract_pois_parameters"]

        cnt = params["cnt"]
        width = params["width"]
        height = params["height"]

        pois = []
        new_pois = []

        for box in bounding_boxes[0]:
            top_left, bottom_right = box
            cnt = cnt + 1
            midpoint = ((top_left[0] + bottom_right[0]) / 2 , (top_left[1] + bottom_right[1]) / 2)

            pois.append((cnt, midpoint[0], midpoint[1], bounding_boxes[1][cnt]))

        for box in pois:
            resized_x = int(box[1]*(floormap_image.shape[1] / width))
            resized_y = int(box[2]*(floormap_image.shape[0]/ height))
            new_pois.append((box[0], resized_x, resized_y, bounding_boxes[1][box[0]]))

        final_pois = self.poi_merge(new_pois, labeled_image)

        return final_pois


    def poi_merge(self, new_pois, labeled_image):
        params = self.config["poi_merge_parameters"]

        poi_threshold = params["poi_threshold"]
        need_merge_poi = []
        final_pois = []

        for poi in new_pois:
            is_find_label = False
            labeled_value = 0
            #find poi label
            for i in range(poi_threshold):
                for j in range(poi_threshold):
                    if labeled_image[poi[2]+i, poi[1]+j] != 0:
                        labeled_value = labeled_image[poi[2]+i, poi[1]+j]
                        is_find_label = True
                    elif labeled_image[poi[2]+i, poi[1]-j] != 0:
                        labeled_value = labeled_image[poi[2]+i, poi[1]-j]
                        is_find_label = True
                    elif labeled_image[poi[2]-i, poi[1]+j] != 0:
                        labeled_value = labeled_image[poi[2]-i, poi[1]+j]
                        is_find_label = True
                    elif labeled_image[poi[2]-i, poi[1]-j] != 0:
                        labeled_value = labeled_image[poi[2]-i, poi[1]-j]
                        is_find_label = True
                    
                    if is_find_label == True:
                        break
                if is_find_label == True:
                    break

            need_merge_poi.append((poi[0],poi[1],poi[2],poi[3], labeled_value))


        for poi in need_merge_poi:
            label_number = poi[4]

            if label_number != 0:
                found_match = False
                combined_text = poi[3]

                for existing_poi in final_pois:
                    if existing_poi[4] == label_number:
                        #if label number exists in final pois, merge it.
                        combined_text += ' ' + existing_poi[3]  

                        #change coordinate into the middle
                        poi = (poi[0], (poi[1] + existing_poi[1]) // 2, (poi[2] + existing_poi[2]) // 2, combined_text, poi[4])

                        final_pois.remove(existing_poi)  # delete it in final_pois
                        final_pois.append(poi)
                        found_match = True
                        break

                if not found_match:
                    final_pois.append(poi)
            else:
                final_pois.append(poi)
        
        return final_pois


    def write_to_json(self, nodes, pois):
        output_nodes = []
        for node in nodes:
            node_dict = {
                "id": f"node{node[0]}",
                "x": int(node[1]),
                "y": int(node[2]),
                "nodeClass": "intersection",
                "outgoingLinks": [{"endNode": f"node{link_id}"} for link_id in node[3]]
            }
            output_nodes.append(node_dict)

        data = {"nodes": output_nodes}

        with open(os.path.join(self.input_image_path_json,"output.json"), "w") as outfile:
            json.dump(data, outfile, indent=4)

        with open(os.path.join(self.input_image_path_json,"map.json"), "w") as outfile:
            json.dump(data, outfile, indent=4)

        #output poi
        poi_list = []
        for poi in pois:
            poi_dict = {
                "id": poi[3],
                "x": int(poi[1]),
                "y": int(poi[2]),
                "nodeClass": "poi",
            }
            poi_list.append(poi_dict)

        data = {"nodes": poi_list}

        with open(os.path.join(self.input_image_path_json,"poi_nodes.json"), "w") as outfile:
            json.dump(data, outfile, indent=4, ensure_ascii=False )

        #output initial
        #find the current location
        initial = []
        flag = False
        for item in pois:
            if '現在地' in item[3] or '現在位置' in item[3]:
                initial.append(item)
                flag = True

        #if not find the current location
        if flag == True:
            initial_node = initial[0]
            output = {
                "nodes": [
                    {
                        "id": "initial_node",
                        "x": initial_node[1],  # x
                        "y": initial_node[2],  # y
                        "nodeClass": "initial",
                        "directionX":0.0,
                        "directionY":0.0
                    }
                ]
            }

            with open(os.path.join(self.input_image_path_json,'initial_node.json'), 'w') as file:
                json.dump(output, file, indent=4)

        else:
            output = {
                "nodes": [
                    {
                        "id": "initial_node",
                        "x": 0,  # x
                        "y": 0,  # y
                        "nodeClass": "initial",
                        "directionX":0.0,
                        "directionY":0.0
                    }
                ]
            }

            with open(os.path.join(self.input_image_path_json,'initial_node.json'), 'w') as file:
                json.dump(output, file, indent=4)


if __name__ == "__main__":
    default_path = 'datasource/floor.png'

    parser = argparse.ArgumentParser(description="MapRecognizer")
    parser.add_argument('--img', type=str, default=default_path, help="Path to the image file")
    args = parser.parse_args()
    
    map_recognizer = MapRecognizer("outputs")
    map_recognizer.recognize_map(args.img)