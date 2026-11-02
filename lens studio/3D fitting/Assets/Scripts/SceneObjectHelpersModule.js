//@module
/**
 * @module SceneObjectHelpersModule
 * Module providing helper functions for SceneObjects and Components.
 * @author Snap Inc.
 * @version 1.1.0
 * 
 * ====  Example ====
 * @example
 * 
 * // Import module
 * var objHelpers = require("./SceneObjectHelpersModule");
 * 
 * // Find object by name
 * var myObj = objHelpers.findObjectWithName("ExampleObject");
 * 
 * // Get list of Visual components in myObj and all children
 * var visuals = objHelpers.getComponentsRecursive(myObj, "Component.Visual");
 * 
 * // Get the first camera that renders the current object
 * var mainCam = objHelpers.getFirstCameraIntersecting( script.getSceneObject().layer);
 *
 * ====  API ====
 * @api
 * 
 * getOrAddComponent(SceneObject object, string componentType): Component
 *      Returns a component of type `componentType` on `object`, or creates a new one and returns it if none is found.
 * 
 * getComponentRecursive(SceneObject object, string componentType): Component
 *      Returns the first Component of `componentType` found in the object or its children.
 * 
 * getComponentsRecursive(SceneObject object, string componentType): Component[]
 *      Returns a list of all Components of `componentType` found in the object and its children.
 * 
 * getComponentInParentRecursive(SceneObject object, string componentType): Component
 *      Returns the first Component of `componentType` found in the object or its parents.
 * 
 * getComponentsInParentRecursive(SceneObject object, string componentType): Component[]
 *      Returns a list of all Components of `componentType` found in the object and its parents.
 * 
 * findObjectWithName(string name): SceneObject
 *      Returns the first SceneObject found with a matching name.
 *      NOTE: This function recursively checks the entire scene and should not be used every frame.
 *      It's recommended to only run this function once and store the result.
 * 
 * findChildObjectWithName(string name): SceneObject
 *      Searches through the children of `sceneObject` and returns the first child found with a matching name.
 *      NOTE: This function recursively checks the entire child hierarchy and should not be used every frame.
 *      It's recommended to only run this function once and store the result.
 * 
 * getFirstParentCameraIntersecting(LayerSet someLayerSet): Camera[]
 *      Returns the first Components.Camera found in the scene intersecting with `someLayerSet`.
 *      NOTE: This function recursively checks the entire child hierarchy and should not be used every frame.
 *      It's recommended to only run this function once and store the result.
 * 
 * getParentCamerasIntersecting(SceneObject object, LayerSet someLayerSet): Camera[]
 *      Returns an array of Component.Camera found on the ancestor of this object.
 *      NOTE: This function recursively checks the entire child hierarchy and should not be used every frame.
 *      It's recommended to only run this function once and store the result.
 * 
 * getFirstDescendantCameraIntersecting(SceneObject object, LayerSet someLayerSet): Camera[]
 *      Returns the first Component.Camera found on the ancestor of this object.
 *      NOTE: This function recursively checks the entire child hierarchy and should not be used every frame.
 *      It's recommended to only run this function once and store the result.
 * 
 * getDescendantCamerasIntersectingRecursive(SceneObject object, LayerSet someLayerSet): Camera[]
 *      Returns an array of Component.Camera found on the ancestor of this object.
 *      NOTE: This function recursively checks the entire child hierarchy and should not be used every frame.
 *      It's recommended to only run this function once and store the result.
 * 
 * getAllCamerasIntersecting(LayerSet someLayerSet): Camera[]
 *      Returns an array of Components.Camera found in the scene intersecting with `someLayerSet`.
 *      NOTE: This function recursively checks the entire child hierarchy and should not be used every frame.
 *      It's recommended to only run this function once and store the result.
 * 
 * getFirstCameraIntersecting(LayerSet someLayerSet): Camera[]
 *      Returns the first Component.Camera found in the scene intersecting with `someLayerSet`.
 *      NOTE: This function recursively checks the entire child hierarchy and should not be used every frame.
 *      It's recommended to only run this function once and store the result.
 *
 */

if (!isNull(script)) {
    throw ("Warning! SceneObjectHelpersModule is a script module. Import this module to your script using:\nvar events = require(\"./SceneObjectHelpersModule\");\nThis script should not be added to a SceneObject.");
}

/**
 * Returns a component of type `componentType` on `object`, or creates a new one and returns it if none is found.
 * @template {keyof ComponentNameMap} T
 * @param {SceneObject} object Object to get Component from, or add Component to
 * @param {T} componentType Component type name
 * @returns {ComponentNameMap[componentType]} Existing or newly created Component
 */
function getOrAddComponent(object, componentType) {
    return object.getComponent(componentType) || object.createComponent(componentType);
}

/**
* Returns the first Component of `componentType` found in the object or its children.
* @template {keyof ComponentNameMap} T
* @param {SceneObject} object Object to search
* @param {T} componentType Component type name to search for
* @returns {ComponentNameMap[componentType]} Matching Component in `object` and its children
*/
function getComponentRecursive(object, componentType) {
    var component = object.getComponent(componentType);
    if (component) {
        return component;
    }
    var childCount = object.getChildrenCount();
    for (var i=0; i<childCount; i++) {
        var result = getComponentRecursive(object.getChild(i), componentType);
        if (result) {
            return result;
        }
    }
    return null;
}

/**
* Returns a list of all Components of `componentType` found in the object and its children.
* @template {keyof ComponentNameMap} T
* @param {SceneObject} object Object to search
* @param {T} componentType Component type name to search for
* @param {ComponentNameMap[componentType][]=} results Optional list to store results in
* @returns {ComponentNameMap[componentType][]} Matching Components in `object` and children
*/
function getComponentsRecursive(object, componentType, results) {
    results = results || [];
    var components = object.getComponents(componentType);
    for (var i=0; i<components.length; i++) {
        results.push(components[i]);
    }
    var childCount = object.getChildrenCount();
    for (var j=0; j<childCount; j++) {
        getComponentsRecursive(object.getChild(j), componentType, results);
    }
    return results;
}

/**
* Returns the first Component of `componentType` found in the object or its parents.
* @template {keyof ComponentNameMap} T
* @param {SceneObject} object Object to search
* @param {T} componentType Component type name to search for
* @returns {ComponentNameMap[componentType]} Matching Component in `object` and its parents
*/
function getComponentInParentRecursive(object, componentType) {
    var component = object.getComponent(componentType);
    if (component) {
        return component;
    }
    if (object.hasParent()) {
        return getComponentInParentRecursive(object.getParent(), componentType);
    }
    return null;
}

/**
* Returns a list of all Components of `componentType` found in the object and its parents.
* @template {keyof ComponentNameMap} T
* @param {SceneObject} object Object to search
* @param {T} componentType Component type name to search for
* @param {ComponentNameMap[componentType][]=} results Optional list to store results in
* @returns {ComponentNameMap[componentType][]} Matching Components in `object` and children
*/
function getComponentsInParentRecursive(object, componentType, results) {
    results = results || [];
    var components = object.getComponents(componentType);
    for (var i=0; i<components.length; i++) {
        results.push(components[i]);
    }
    if (object.hasParent()) {
        getComponentsInParentRecursive(object.getParent(), componentType, results);
    }
    return results;
}


/**
 * Returns the first SceneObject found with a matching name.
 * NOTE: This function recursively checks the entire scene and should not be used every frame.
 * It's recommended to only run this function once and store the result.
 * @param {string} objectName Object name to search for
 * @returns {SceneObject?} Found object (if any)
 */
function findObjectWithName(objectName) {
    var rootObjectCount = global.scene.getRootObjectsCount();
    var obj;
    var res;
    for (var i=0; i< rootObjectCount; i++) {
        obj = global.scene.getRootObject(i);
        if (obj.name == objectName) {
            return obj;
        }
        res = findChildObjectWithName(global.scene.getRootObject(i), objectName);
        if (res) {
            return res;
        }
    }
    return null;
}

/**
 * Searches through the children of `sceneObject` and returns the first child found with a matching name.
 * NOTE: This function recursively checks the entire child hierarchy and should not be used every frame.
 * It's recommended to only run this function once and store the result.
 * @param {SceneObject} sceneObject Parent object to search the children of
 * @param {string} childName Object name to search for
 * @returns {SceneObject?} Found object (if any)
 */
function findChildObjectWithName(sceneObject, childName) {
    var childCount = sceneObject.getChildrenCount();
    var child;
    var res;
    for (var i=0; i<childCount; i++) {
        child = sceneObject.getChild(i);
        if (child.name == childName) {
            return child;
        }
        res = findChildObjectWithName(child, childName);
        if (res) {
            return res;
        }
    }
    return null;
}

/**
 * Returns the first Component.Camera found on the ancestor of this object.
 * NOTE: This function recursively checks the entire parent hierarchy and should not be used every frame.
 * It's recommended to only run this function once and store the result.
 * @param {SceneObject} object The object whose ancestor we want to look through
 * @param {LayerSet=} someLayerSet The LayerSet which to test for intersection
 * @returns {Camera?}
 */
function getFirstParentCameraIntersectingRecursive(object, passedInLayerSet) {
    var someLayerSet = passedInLayerSet ? passedInLayerSet : object.layer;
    var camera = object.getComponent("Component.Camera");
    if (camera) {
        if ( 
            !camera.renderLayer.intersect(someLayerSet).isEmpty()
        ) {
            return camera;
        }
    }
    if (object.hasParent()) {
        return getFirstParentCameraIntersectingRecursive(object.getParent(), someLayerSet);
    }
    return null;
}

/**
 * Returns all Component.Camera found on the ancestor of this object.
 * NOTE: This function recursively checks the entire parent hierarchy and should not be used every frame.
 * It's recommended to only run this function once and store the result.
 * @param {SceneObject} object The object whose ancestor we want to look through
 * @param {LayerSet=} someLayerSet The LayerSet which to test for intersection
 * @returns {Camera?}
 */
function getParentCamerasIntersectingRecursive(object, passedInLayerSet) {
    var someLayerSet = passedInLayerSet ? passedInLayerSet : object.layer;
    var cameras = [];
    var camComponents = object.getComponents("Component.Camera");
    for (var i = 0; i < camComponents.length; i++) {
        var camComponent = camComponents[i];
        if ( 
            !camComponent.renderLayer.intersect(someLayerSet).isEmpty()
        ) {
            cameras.push(camComponent);
        }
    }
    if (object.hasParent()) {
        var foundCameras = getParentCamerasIntersectingRecursive(object.getParent(), someLayerSet);
        cameras = cameras.concat(foundCameras);
    }
    return cameras;
}

/**
 * Returns the first Component.Camera found under an object intersecting with `someLayerSet`.
 * NOTE: This function recursively checks the entire child hierarchy and should not be used every frame.
 * It's recommended to only run this function once and store the result.
 * @param {SceneObject} object the object whose descendants we want to look through.
 * @param {LayerSet=} someLayerSet The LayerSet which to test for intersection
 * @returns {Camera[]}
 */
function getFirstDescendantCameraIntersectingRecursive(object, passedInLayerSet) {
    var someLayerSet = passedInLayerSet ? passedInLayerSet : object.layer;
    var camera = object.getComponent("Component.Camera");
    if (camera) {
        if ( 
            !camera.renderLayer.intersect(someLayerSet).isEmpty()
        ) {
            return camera;
        }
    }
    for (var i = 0; i < object.children.length; i++) {
        var foundCam = getFirstDescendantCameraIntersectingRecursive(object.children[i], someLayerSet);
        if (foundCam) {
            return foundCam;
        }
    }
    return null;
}

/**
 * Returns an array of Component.Camera found under an object intersecting with `someLayerSet`.
 * NOTE: This function recursively checks the entire child hierarchy and should not be used every frame.
 * It's recommended to only run this function once and store the result.
 * @param {SceneObject} object the object whose descendants we want to look through.
 * @param {LayerSet=} someLayerSet The LayerSet which to test for intersection
 * @returns {Camera[]}
 */
function getDescendantCamerasIntersectingRecursive(object, passedInLayerSet) {
    var someLayerSet = passedInLayerSet ? passedInLayerSet : object.layer;
    var cameras = [];
    var camComponents = object.getComponents("Component.Camera");
    for (var i = 0; i < camComponents.length; i++) {
        var camComponent = camComponents[i];
        if ( 
            !camComponent.renderLayer.intersect(someLayerSet).isEmpty()
        ) {
            cameras.push(camComponent);
        }
    }
    for (var j = 0; j < object.children.length; j++) {
        var foundCameras = getDescendantCamerasIntersectingRecursive(object.children[j], someLayerSet);
        cameras = cameras.concat(foundCameras);
    }
    return cameras;
}

/**
 * Searches through every `sceneObject` and returns an array of Component.Camera found in the scene intersecting with `someLayerSet`.
 * NOTE: This function recursively checks the entire child hierarchy and should not be used every frame.
 * It's recommended to only run this function once and store the result.
 * @param {LayerSet} someLayerSet The LayerSet which to test for intersection
 * @returns {Camera[]}
 */
function getAllCamerasIntersecting(someLayerSet) {
    var rootObjectsCount = global.scene.getRootObjectsCount();
    var cameras = [];
    for (var i = 0; i < rootObjectsCount; i++) {
        var foundCameras = getDescendantCamerasIntersectingRecursive(global.scene.getRootObject(i), someLayerSet);
        cameras = cameras.concat(foundCameras);
    }
    return cameras;
}

/**
 * Searches through every `sceneObject` and returns the first Component.Camera found in the scene intersecting with `someLayerSet`.
 * NOTE: This function recursively checks the entire child hierarchy and should not be used every frame.
 * It's recommended to only run this function once and store the result.
 * @param {LayerSet} someLayerSet The LayerSet which to test for intersection
 * @returns {Camera}
 */
function getFirstCameraIntersecting(someLayerSet) {
    var rootObjectsCount = global.scene.getRootObjectsCount();
    for (var i = 0; i < rootObjectsCount; i++) {
        var foundCam = getFirstDescendantCameraIntersectingRecursive(global.scene.getRootObject(i), someLayerSet);
        if (foundCam) {
            return foundCam;
        }
    }
    return null;
}

module.exports.version = "1.1.0";
module.exports.getOrAddComponent = getOrAddComponent;
module.exports.getComponentRecursive = getComponentRecursive;
module.exports.getComponentsRecursive = getComponentsRecursive;
module.exports.getComponentInParentRecursive = getComponentInParentRecursive;
module.exports.getComponentsInParentRecursive = getComponentsInParentRecursive;
module.exports.findObjectWithName = findObjectWithName;
module.exports.findChildObjectWithName = findChildObjectWithName;
module.exports.getFirstParentCameraIntersectingRecursive = getFirstParentCameraIntersectingRecursive;
module.exports.getParentCamerasIntersectingRecursive = getParentCamerasIntersectingRecursive;
module.exports.getFirstDescendantCameraIntersectingRecursive = getFirstDescendantCameraIntersectingRecursive;
module.exports.getDescendantCamerasIntersectingRecursive = getDescendantCamerasIntersectingRecursive;
module.exports.getAllCamerasIntersecting = getAllCamerasIntersecting;
module.exports.getFirstCameraIntersecting = getFirstCameraIntersecting;
