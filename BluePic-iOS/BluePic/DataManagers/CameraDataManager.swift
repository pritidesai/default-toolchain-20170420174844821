/**
 * Copyright IBM Corporation 2016
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

import UIKit
import ImageIO
import CoreLocation

enum CameraDataManagerNotification: String {
    case UserPressedPostPhoto = "UserPressedPostPhoto"

}

/// Singleton to hold any state with showing the camera picker. Allows user to upload a photo to BluePic
class CameraDataManager: NSObject {

    /// Shared instance of data manager to make the CameraDataManager a singleton
    static let SharedInstance: CameraDataManager = {

        var manager = CameraDataManager()

        return manager

    }()
    
    //reference to the tab bar vc
    var tabVC: TabBarViewController!
    
    //image picker
    var picker: UIImagePickerController!
    
    //confirmationView to be shown after selecting or taking a photo
    var confirmationView: CameraConfirmationView!
    
    //instance of the image the user decided to post
    var imageUserDecidedToPost : Image!
    
    //state variables
    var failureGettingUserLocation = false

    var userPressedPostPhoto = false
    
    //Constant for how wide all images should be constrained to when compressing for upload (600 results in ~1.2 MB photos)
    let kResizeAllImagesToThisWidth = CGFloat(600)
    
    //what we make the image objects caption if the user doesn't put a caption
    let kEmptyCaptionPlaceHolder = "No-Caption"
    
    /**
     prevents others from using the default '()' initializer for this class
     
     - returns:
     */
    private override init() {}
    
    
    /**
     Method to show the image picker action sheet so user can choose from Photo Library or Camera

     - parameter presentingVC: tab VC to present over top of
     */
    func showImagePickerActionSheet(presentingVC: TabBarViewController) {
        self.tabVC = presentingVC
        self.picker = UIImagePickerController()
        let alert: UIAlertController=UIAlertController(title: nil, message: nil, preferredStyle: UIAlertControllerStyle.ActionSheet)
        let cameraAction = UIAlertAction(title: NSLocalizedString("Photo Library", comment: ""), style: UIAlertActionStyle.Default) {
                UIAlertAction in
                self.openGallery()
        }
        let galleryAction = UIAlertAction(title: NSLocalizedString("Take Photo", comment: ""), style: UIAlertActionStyle.Default) {
                UIAlertAction in
                self.openCamera()
        }
        let cancelAction = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: UIAlertActionStyle.Cancel) {
                UIAlertAction in
        }

        // Add the actions
        picker?.delegate = self
        alert.addAction(cameraAction)
        alert.addAction(galleryAction)
        alert.addAction(cancelAction)

        // on iPad, this will be a Popover
        // on iPhone, this will be an action sheet
        alert.modalPresentationStyle = .Popover


        // Present the controller
        self.tabVC.presentViewController(alert, animated: true, completion: nil)

    }

    /**
     Method called when user wants to take a photo with the camera
     */
    func openCamera() {
        if UIImagePickerController .isSourceTypeAvailable(UIImagePickerControllerSourceType.Camera) {

            picker.sourceType = UIImagePickerControllerSourceType.Camera
            self.tabVC.presentViewController(picker, animated: true, completion: { _ in
                self.showCameraConfirmation()
            })
        } else {
            openGallery()
        }
    }

    /**
     Method called when user wants to choose a photo from Photo Album for posting
     */
    func openGallery() {
        picker.sourceType = UIImagePickerControllerSourceType.PhotoLibrary
        self.tabVC.presentViewController(picker, animated: true, completion: { _ in
            self.showCameraConfirmation()
        })

    }

    /**
     Method to show the camera confirmation view for adding a caption and posting
     */
    func showCameraConfirmation() {
        self.confirmationView = CameraConfirmationView.instanceFromNib()
        self.confirmationView.frame = CGRect(x: 0, y: 0, width: self.tabVC.view.frame.width, height: self.tabVC.view.frame.height)
        self.confirmationView.originalFrame = self.confirmationView.frame

        //set up button actions
        self.confirmationView.cancelButton.addTarget(self, action: #selector(CameraDataManager.dismissCameraConfirmation), forControlEvents: .TouchUpInside)
        self.confirmationView.postButton.addTarget(self, action: #selector(CameraDataManager.postPhotoButtonAction), forControlEvents: .TouchUpInside)

        //show view
        self.tabVC.view.addSubview(self.confirmationView)
    }
    
    
    /**
     Method resets the state variables
     */
    private func resetStateVariables(){
        
        imageUserDecidedToPost = nil
        failureGettingUserLocation = false
        userPressedPostPhoto = false

    }
    
    /**
     Method shows the progress hud and disables UI
     */
    private func showProgressHudAndDisableUI(){
        self.confirmationView.titleTextField.resignFirstResponder()
        self.confirmationView.disableUI()

        SVProgressHUD.show()

    }
    
    /**
     Method dismisses the progress hud and re-enables the UI
     */
    private func dismissProgressHUDAndReEnableUI(){
        
        self.confirmationView.enableUI()
        SVProgressHUD.dismiss()

    }
    
    /**
     Method to hide the confirmation view when cancelling or done uploading
     */
    func dismissCameraConfirmation() {
        UIApplication.sharedApplication().statusBarHidden = false
        self.confirmationView.loadingIndicator.stopAnimating()
        self.confirmationView.endEditing(true) //dismiss keyboard first if shown
        UIView.animateWithDuration(0.4, animations: { _ in
            self.confirmationView.frame = CGRect(x: 0, y: self.tabVC.view.frame.height, width: self.tabVC.view.frame.width, height: self.tabVC.view.frame.height)
            }, completion: { _ in
                self.destroyConfirmationView()
                self.tabVC.view.userInteractionEnabled = true
                print("picker dismissed from confirmation view.")
        })

    }

    /**
     Method to remove the confirmation view from memory when finished with it
     */
    func destroyConfirmationView() {
        self.confirmationView.removeKeyboardObservers()
        self.confirmationView.removeFromSuperview()
        self.confirmationView = nil
    }

    /**
     Alert to be shown if photo couldn't be loaded from disk (iCloud photo stream photo not loaded, for example)
     */
    func showPhotoCouldntBeChosenAlert() {
        let alert = UIAlertController(title: nil, message: NSLocalizedString("This photo couldn't be loaded. Please use a different one!", comment: ""), preferredStyle: UIAlertControllerStyle.Alert)

        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: ""), style: .Default, handler: { (action: UIAlertAction) in
            self.openGallery()
        }))

        dispatch_async(dispatch_get_main_queue()) {
            self.tabVC.presentViewController(alert, animated: true, completion: nil)
        }

    }

    /**
     Method to rotate image taken if necessary

     - parameter imageToRotate: UIImage

     - returns: UIImage
     */
    func rotateImageIfNecessary(imageToRotate: UIImage) -> UIImage {
        let imageOrientation = imageToRotate.imageOrientation.rawValue
        switch imageOrientation {
        case 0: //Up
            return imageToRotate.imageRotatedByDegrees(0, flip: false)
        case 1: //Down
            return imageToRotate.imageRotatedByDegrees(180, flip: false)
        case 2: //Left
            return imageToRotate.imageRotatedByDegrees(270, flip: false)
        case 3: //Right
            return imageToRotate.imageRotatedByDegrees(90, flip: false)
        default:
            return imageToRotate.imageRotatedByDegrees(0, flip: false)
        }
    }

}

//All methods related to uploading an image
extension CameraDataManager: UIImagePickerControllerDelegate {
    
    /**
     Method is called after the user takes a photo or chooses a photo from their photo library. This method will save information about the photo taken which will help us handle errors if the photo fails to save and upload to cloudant and object storage

     - parameter picker: UIImagePickerController
     - parameter info:   [String : AnyObject]
     */
    func imagePickerController(picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : AnyObject]) {
        picker.dismissViewControllerAnimated(true, completion: nil)

        resetStateVariables()

        //show image on confirmationView, save a copy
        if let takenImage = info[UIImagePickerControllerOriginalImage] as? UIImage {

            prepareimageUserDecidedToPost(takenImage)

            //set the confirmation view's photoImageView with the photo just chosen/taken
            self.confirmationView.photoImageView.image = takenImage

        }
        //if image isn't available (iCloud photo in Photo stream not loaded yet)
        else {
            self.destroyConfirmationView()
            picker.dismissViewControllerAnimated(true, completion: { _ in

            })
            self.showPhotoCouldntBeChosenAlert()
            print("picker canceled - photo not available!")

        }
    }

    /**
     Method creates an image open from the the image the user decided to post and preps all of its properties with data
     
     - parameter takenImage: UIImage
     */
    func prepareimageUserDecidedToPost(takenImage : UIImage) {
        
        guard let userId = CurrentUser.facebookUserId, fullName = CurrentUser.fullName else {
            print("Failed to create user object")
            return
        }
        let userObject = User(facebookID: userId, name: fullName)

        var image: UIImage
        if takenImage.size.width > kResizeAllImagesToThisWidth { //if image too big, shrink it down
            image = UIImage.resizeImage(takenImage, newWidth: kResizeAllImagesToThisWidth)
        } else {
            image = takenImage
        }

        image = self.rotateImageIfNecessary(image)

        //save name of image as current date and time
        let dateFormatter = NSDateFormatter()
        dateFormatter.dateFormat = "MM-dd-yyyy_HHmmss"
        let todaysDate = NSDate()
        let fileName = dateFormatter.stringFromDate(todaysDate) + ".png"
        
        setLatLongAndLocationNameForImage { location in
          
            if let location = location {
                self.imageUserDecidedToPost = Image(caption: "", fileName: fileName, width: image.size.width, height: image.size.height, image: image, location: location, user: userObject)

            } else {
                self.failureGettingUserLocation = true
            }

            self.tryToPostPhoto()

        }

    }
    
    
    /**
     Method is called when the post button is pressed
     */
    func postPhotoButtonAction(){
        userPressedPostPhoto = true

        tryToPostPhoto()
    }
    
    /**
     Method tries to post the photo only if the user has pressed the post photo button already.
     */
    private func tryToPostPhoto(){
        
        //only post photo if user has chosen to
        if userPressedPostPhoto {

            //failure getting user location
            if failureGettingUserLocation == true {
                self.showCantDetermineLocationAlert()
            }
            //location determined
            else if imageUserDecidedToPost != nil {
                postPhoto()
            }
            //location still being determined
            else if imageUserDecidedToPost == nil {
                showProgressHudAndDisableUI()
            }
        }

    }

    /**
     Method called if the tryToPostPhoto checks pass. It will update the image object with the caption the user wrote and then tell the BluemixDataManager to begin posting the new image. Then it dismisses the camera confirmation view.
     */
    func postPhoto() {

        dismissProgressHUDAndReEnableUI()

        self.confirmationView.endEditing(true) //dismiss keyboard first if shown
        self.confirmationView.userInteractionEnabled = false
        self.tabVC.view.userInteractionEnabled = false
        self.confirmationView.loadingIndicator.startAnimating()
        self.confirmationView.cancelButton.hidden = true
        self.confirmationView.postButton.hidden = true

        //add caption of image
        if let text = self.confirmationView.titleTextField.text where text != "" {
            imageUserDecidedToPost.caption = text
        } else {
            imageUserDecidedToPost.caption = kEmptyCaptionPlaceHolder
        }

        dispatch_async(dispatch_get_main_queue()) {
            BluemixDataManager.SharedInstance.postNewImage(self.imageUserDecidedToPost)
        }

        //Dismiss Camera Confirmation View when user presses post photo to bring user back to image feed
        dismissCameraConfirmation()

    }
    
 
    /**
     Method shows the location can't be determined alert
     */
    func showCantDetermineLocationAlert(){
        
        dismissProgressHUDAndReEnableUI()

        let alert = UIAlertController(title: NSLocalizedString("Location Not Found", comment: ""), message: NSLocalizedString("Location is required to post a photo", comment: ""), preferredStyle: UIAlertControllerStyle.Alert)

        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .Default, handler: { (action: UIAlertAction) in

        }))

        alert.addAction(UIAlertAction(title: NSLocalizedString("Try Again", comment: ""), style: .Default, handler: { (action: UIAlertAction) in
            
            self.tryToDetermineLocationAgainAndSetLatLongAndLocationName()
            
        }))

        dispatch_async(dispatch_get_main_queue()) {
            self.tabVC.presentViewController(alert, animated: true, completion: nil)
        }

    }
    
    /**
     Method sets the latitude, longitude, and location name for the image by asking the LocationDataManager for this information
     
     - parameter callback: ((location : Location?)->())
     */
    private func setLatLongAndLocationNameForImage(callback : ((location : Location?)->())){
   
        LocationDataManager.SharedInstance.getCurrentLatLongCityAndState(){ (latitude : CLLocationDegrees?, longitude : CLLocationDegrees?, city : String?, state : String?, error : LocationDataManagerError?) in
            
            //failure
            if error != nil {
                callback(location: nil)
            }
            //success
            else if let latitude = latitude,
                longitude = longitude,
                city = city,
                state = state {

                let location = Location(name: "\(city), \(state)", latitude: "\(latitude)", longitude: "\(longitude)", weather: nil)

                callback(location: location)
            }
            //failure
            else {
                callback(location: nil)
            }

        }
    }
    
    /**
     Method is called from can't determine location alert if the user chooses to retry getting the location for the image
     */
    private func tryToDetermineLocationAgainAndSetLatLongAndLocationName(){
        
        showProgressHudAndDisableUI()

        failureGettingUserLocation = false
        
        setLatLongAndLocationNameForImage { location in
            
            self.dismissProgressHUDAndReEnableUI()

            if location == nil {
                self.failureGettingUserLocation = true
            }
            self.tryToPostPhoto()
            
        }

    }

    /**
     Method is called when the user decides to cancel taking a photo or choosing a photo from their photo library.

     - parameter picker: UIImagePickerController
     */
    func imagePickerControllerDidCancel(picker: UIImagePickerController) {
        self.destroyConfirmationView()
        picker.dismissViewControllerAnimated(true, completion: nil)

        print("picker canceled.")
    }

}

extension CameraDataManager: UINavigationControllerDelegate {

}
