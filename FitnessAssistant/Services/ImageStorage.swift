import Foundation
import UIKit

enum ImageStorage {
    static func compressedJPEGData(from image: UIImage, quality: CGFloat = 0.72, maxDimension: CGFloat = 1280) -> Data? {
        let resized = image.resized(maxDimension: maxDimension)
        return resized.jpegData(compressionQuality: quality)
    }

    static func saveMealPhoto(data: Data) throws -> String {
        let directory = try mealPhotoDirectory()
        let fileName = "\(UUID().uuidString).jpg"
        let url = directory.appendingPathComponent(fileName)
        try data.write(to: url, options: [.atomic])
        return fileName
    }

    static func mealPhotoURL(fileName: String) -> URL? {
        guard let directory = try? mealPhotoDirectory() else { return nil }
        return directory.appendingPathComponent(fileName)
    }

    private static func mealPhotoDirectory() throws -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("MealPhotos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }
}

private extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
