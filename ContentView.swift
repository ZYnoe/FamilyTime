import SwiftUI
import UIKit
import PhotosUI

// Data model: 每个 Moment 包含日期、描述、多张图片数据和情绪值。
struct Moment: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var description: String
    var imageDatas: [Data] = []  // 支持多张图片
    var emotion: Double          // 0.0 表示 sad/negative, 1.0 表示 happy/positive
}

// ViewModel: 管理 CRUD 操作、保存以及 PDF 导出。
class MomentsViewModel: ObservableObject {
    @Published var moments: [Moment] = []
    private let momentsKey = "moments_key"

    init() {
        loadMoments()
    }

    // 添加新的 moment
    func addMoment(description: String, imageDatas: [Data] = [], emotion: Double = 0.5) {
        let newMoment = Moment(date: Date(), description: description, imageDatas: imageDatas, emotion: emotion)
        moments.append(newMoment)
        saveMoments()
    }

    // 更新已有的 moment —— 编辑功能使用
    func updateMoment(_ updatedMoment: Moment) {
        if let index = moments.firstIndex(where: { $0.id == updatedMoment.id }) {
            moments[index] = updatedMoment
            saveMoments()
        }
    }

    // 根据 id 删除 moments
    func deleteMoments(matching ids: [UUID]) {
        moments.removeAll { ids.contains($0.id) }
        saveMoments()
    }

    // 从 UserDefaults 加载数据
    func loadMoments() {
        if let data = UserDefaults.standard.data(forKey: momentsKey),
           let savedMoments = try? JSONDecoder().decode([Moment].self, from: data) {
            moments = savedMoments
        }
    }

    // 保存数据到 UserDefaults
    func saveMoments() {
        if let data = try? JSONEncoder().encode(moments) {
            UserDefaults.standard.set(data, forKey: momentsKey)
        }
    }

    // 导出所有 moments 为 PDF
    func exportPDF() -> Data? {
        let pageWidth: CGFloat = 612    // US Letter width
        let pageHeight: CGFloat = 792   // US Letter height
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { context in
            for moment in moments {
                context.beginPage()

                // 绘制日期
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                let dateText = dateFormatter.string(from: moment.date)
                let dateAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16)
                ]
                let dateRect = CGRect(x: 20, y: 20, width: pageWidth - 40, height: 20)
                dateText.draw(in: dateRect, withAttributes: dateAttributes)

                // 绘制描述
                let descriptionAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 16)
                ]
                let descriptionRect = CGRect(x: 20, y: 50, width: pageWidth - 40, height: 50)
                moment.description.draw(in: descriptionRect, withAttributes: descriptionAttributes)

                // 绘制情绪滑条
                let sliderX: CGFloat = 20
                let sliderY: CGFloat = 110
                let sliderWidth: CGFloat = pageWidth - 40
                let sliderHeight: CGFloat = 4
                let sliderRect = CGRect(x: sliderX, y: sliderY, width: sliderWidth, height: sliderHeight)
                UIColor.lightGray.setFill()
                UIBezierPath(roundedRect: sliderRect, cornerRadius: sliderHeight / 2).fill()

                // 绘制情绪标记
                let markerDiameter: CGFloat = 10
                let markerX = sliderX + sliderWidth * CGFloat(moment.emotion) - markerDiameter / 2
                let markerY = sliderY - (markerDiameter - sliderHeight) / 2
                let markerRect = CGRect(x: markerX, y: markerY, width: markerDiameter, height: markerDiameter)
                UIColor.darkGray.setFill()
                UIBezierPath(ovalIn: markerRect).fill()

                // 设置图片绘制的起始 Y 坐标
                var currentY: CGFloat = sliderY + markerDiameter + 10
                let bottomMargin: CGFloat = 20

                // 绘制每一张图片
                for imageData in moment.imageDatas {
                    if let image = UIImage(data: imageData) {
                        let availableWidth = pageWidth - 40
                        let imageAspect = image.size.height / image.size.width
                        let imageHeight = availableWidth * imageAspect

                        if currentY + imageHeight > pageHeight - bottomMargin {
                            context.beginPage()
                            currentY = 20
                        }

                        let imageRect = CGRect(x: 20, y: currentY, width: availableWidth, height: imageHeight)
                        image.draw(in: imageRect)
                        currentY += imageHeight + 10
                    }
                }
            }
        }
        return data
    }
}

// 主视图: 显示所有 moments，并提供导出 PDF、新增 moment、删除和编辑功能。
struct ContentView: View {
    @StateObject var viewModel = MomentsViewModel()
    @State private var showingAddMoment = false
    @State private var showingShareSheet = false
    @State private var shareItems: [Any] = []

    // 用于长按放大图片的状态变量
    @State private var selectedImage: UIImage? = nil
    @State private var showingFullScreenImage = false

    var body: some View {
        NavigationView {
            let sortedMoments = viewModel.moments.sorted(by: { $0.date > $1.date })
            List {
                ForEach(sortedMoments) { moment in
                    NavigationLink(destination: EditMomentView(viewModel: viewModel, moment: moment)) {
                        VStack(alignment: .leading, spacing: 10) {
                            // 主列表里图片以横向滚动展示
                            if !moment.imageDatas.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        ForEach(moment.imageDatas, id: \.self) { imageData in
                                            if let uiImage = UIImage(data: imageData) {
                                                Image(uiImage: uiImage)
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(width: 200, height: 200)
                                                    .cornerRadius(8)
                                                    .onLongPressGesture {
                                                        selectedImage = uiImage
                                                        showingFullScreenImage = true
                                                    }
                                            }
                                        }
                                    }
                                }
                            }
                            Text(moment.description)
                                .font(.headline)
                            Text({
                                let formatter = DateFormatter()
                                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                                return formatter.string(from: moment.date)
                            }())
                            .font(.subheadline)
                            .foregroundColor(.gray)

                            // 显示情绪滑条（禁用交互）
                            HStack {
                                Text("Sad")
                                Slider(value: .constant(moment.emotion), in: 0...1)
                                    .disabled(true)
                                Text("Happy")
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .onDelete { indexSet in
                    let idsToDelete = indexSet.map { sortedMoments[$0].id }
                    viewModel.deleteMoments(matching: idsToDelete)
                }
            }
            .navigationTitle("Family Moments")
            .navigationBarItems(
                leading: Button("Export PDF") {
                    if let pdfData = viewModel.exportPDF() {
                        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("moments.pdf")
                        do {
                            try pdfData.write(to: tempURL)
                            shareItems = [tempURL]
                            showingShareSheet = true
                        } catch {
                            print("Failed to write PDF file: \(error)")
                        }
                    }
                },
                trailing: Button(action: {
                    showingAddMoment = true
                }) {
                    Image(systemName: "plus")
                }
            )
            .sheet(isPresented: $showingAddMoment) {
                AddMomentView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingShareSheet) {
                ActivityView(activityItems: shareItems)
            }
        }
        // 全屏展示放大图片
        .fullScreenCover(isPresented: $showingFullScreenImage) {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack {
                    Spacer()
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .padding()
                    }
                    Spacer()
                    Button(action: {
                        showingFullScreenImage = false
                    }) {
                        Text("Close")
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.gray.opacity(0.7))
                            .cornerRadius(8)
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }
}

// 添加 Moment 的视图：使用 LazyVGrid 实现九宫格布局，并支持上下滚动查看所有图片。
struct AddMomentView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var viewModel: MomentsViewModel
    @State private var description: String = ""
    @State private var selectedImages: [UIImage] = []  // 存储选中的多张图片
    @State private var emotion: Double = 0.5           // 默认中性情绪
    @State private var showingImagePicker = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Record a Beautiful Moment")) {
                    TextField("Write down your mood...", text: $description)
                }
                Section(header: Text("Emotion")) {
                    HStack {
                        Text("Sad")
                        Slider(value: $emotion, in: 0...1)
                        Text("Happy")
                    }
                }
                Section(header: Text("Attach Photos")) {
                    if !selectedImages.isEmpty {
                        let columns = [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ]
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(selectedImages, id: \.self) { image in
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipped()
                                        .cornerRadius(8)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                    Button(action: {
                        showingImagePicker = true
                    }) {
                        Text(selectedImages.isEmpty ? "Choose Photos" : "Add Another")
                    }
                }
            }
            .navigationTitle("Add Moment")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    let imageDatas = selectedImages.compactMap { $0.jpegData(compressionQuality: 0.8) }
                    viewModel.addMoment(description: description, imageDatas: imageDatas, emotion: emotion)
                    presentationMode.wrappedValue.dismiss()
                }
                .disabled(description.isEmpty)
            )
            .sheet(isPresented: $showingImagePicker) {
                PhotoPicker(selectedImages: $selectedImages)
            }
        }
    }
}

// 编辑 Moment 的视图：支持修改描述、情绪和附加的图片（以九宫格展示，可删除图片）。
struct EditMomentView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var viewModel: MomentsViewModel
    var moment: Moment

    @State private var description: String
    @State private var selectedImages: [UIImage]
    @State private var emotion: Double
    @State private var showingImagePicker = false

    init(viewModel: MomentsViewModel, moment: Moment) {
        self.viewModel = viewModel
        self.moment = moment
        _description = State(initialValue: moment.description)
        _emotion = State(initialValue: moment.emotion)
        let images = moment.imageDatas.compactMap { UIImage(data: $0) }
        _selectedImages = State(initialValue: images)
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Edit Your Moment")) {
                    TextField("Update your description...", text: $description)
                }
                Section(header: Text("Emotion")) {
                    HStack {
                        Text("Sad")
                        Slider(value: $emotion, in: 0...1)
                        Text("Happy")
                    }
                }
                Section(header: Text("Attached Photos")) {
                    if !selectedImages.isEmpty {
                        let columns = [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ]
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(selectedImages.indices, id: \.self) { index in
                                    ZStack(alignment: .topTrailing) {
                                        Image(uiImage: selectedImages[index])
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 100, height: 100)
                                            .clipped()
                                            .cornerRadius(8)
                                        Button(action: {
                                            selectedImages.remove(at: index)
                                        }) {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundColor(.red)
                                        }
                                        .offset(x: 5, y: -5)
                                    }
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                    Button(action: {
                        showingImagePicker = true
                    }) {
                        Text(selectedImages.isEmpty ? "Choose Photos" : "Add Another")
                    }
                }
            }
            .navigationTitle("Edit Moment")
            .navigationBarItems(
                leading: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                },
                trailing: Button("Save") {
                    let imageDatas = selectedImages.compactMap { $0.jpegData(compressionQuality: 0.8) }
                    let updatedMoment = Moment(id: moment.id, date: moment.date, description: description, imageDatas: imageDatas, emotion: emotion)
                    viewModel.updateMoment(updatedMoment)
                    presentationMode.wrappedValue.dismiss()
                }
                .disabled(description.isEmpty)
            )
            .sheet(isPresented: $showingImagePicker) {
                PhotoPicker(selectedImages: $selectedImages)
            }
        }
    }
}

// PhotoPicker: 使用 PHPickerViewController 支持多图选择
struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 0  // 0 表示无限制选择
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker

        init(_ parent: PhotoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            for result in results {
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] image, error in
                        guard let self = self, let image = image as? UIImage else { return }
                        DispatchQueue.main.async {
                            self.parent.selectedImages.append(image)
                        }
                    }
                }
            }
        }
    }
}

// ActivityView: 用于分享文件的包装视图
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// SwiftUI 预览
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

