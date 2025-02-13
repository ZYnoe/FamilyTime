import SwiftUI
import UIKit
import PhotosUI
import PDFKit

    // MARK: - Data Model
    
    struct Moment: Identifiable, Codable, Sendable {
        var id = UUID()
        var date: Date
        var description: String
        var imageDatas: [Data] = []  // 存储多张图片数据
        var emotion: Double          // 0.0 = sad, 1.0 = happy
    }
    
    // MARK: - DateFormatter Extension
    
    extension DateFormatter {
        static let momentFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return formatter
        }()
    }
    
    // MARK: - MomentsViewModel
    
    class MomentsViewModel: ObservableObject {
        @Published var moments: [Moment] = []
        private let momentsKey = "moments_key"
        
        init() {
            loadMoments()
        }
        
        func addMoment(description: String, imageDatas: [Data] = [], emotion: Double = 0.5) {
            let newMoment = Moment(date: Date(), description: description, imageDatas: imageDatas, emotion: emotion)
            moments.append(newMoment)
            saveMoments()
        }
        
        func updateMoment(_ updatedMoment: Moment) {
            if let index = moments.firstIndex(where: { $0.id == updatedMoment.id }) {
                moments[index] = updatedMoment
                saveMoments()
            }
        }
        
        func deleteMoments(matching ids: [UUID]) {
            moments.removeAll { ids.contains($0.id) }
            saveMoments()
        }
        
        // 从 UserDefaults 加载数据，并捕获错误
        func loadMoments() {
            if let data = UserDefaults.standard.data(forKey: momentsKey) {
                do {
                    let saved = try JSONDecoder().decode([Moment].self, from: data)
                    moments = saved
                } catch {
                    print("加载数据失败: \(error.localizedDescription)")
                }
            }
        }
        
        // 保存数据到 UserDefaults，并捕获错误
        func saveMoments() {
            do {
                let data = try JSONEncoder().encode(moments)
                UserDefaults.standard.set(data, forKey: momentsKey)
            } catch {
                print("保存数据失败: \(error.localizedDescription)")
            }
        }
        
        // MARK: - 改造后的导出 PDF 逻辑
        /// 对外提供的导出 PDF 方法：先拷贝数据，再在后台调用静态函数，最后主线程回调
        func exportPDF(completion: @escaping (Data?) -> Void) {
            // 先把 moments 拷贝出来，避免闭包捕获整个 self
            let momentsCopy = moments
            
            let pageWidth: CGFloat = 612    // US Letter 宽度
            let pageHeight: CGFloat = 792   // US Letter 高度
            let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
            
            // 后台线程执行 PDF 渲染
            DispatchQueue.global(qos: .userInitiated).async {
                // 只用静态函数 + momentsCopy，不捕获 self 和非 Sendable 的东西
                let pdfData = Self.createPDFData(moments: momentsCopy, pageRect: pageRect)
                
                // 回到主线程把结果传出去
                DispatchQueue.main.async {
                    completion(pdfData)
                }
            }
        }
        
        /// 静态函数：纯粹根据给定的 moments 和页面尺寸生成 PDF 的 Data
        private static func createPDFData(moments: [Moment], pageRect: CGRect) -> Data {
            let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
            
            return renderer.pdfData { context in
                for moment in moments {
                    context.beginPage()
                    
                    // 绘制日期
                    let dateText = DateFormatter.momentFormatter.string(from: moment.date)
                    let dateAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 16)]
                    let dateRect = CGRect(x: 20, y: 20, width: pageRect.width - 40, height: 20)
                    dateText.draw(in: dateRect, withAttributes: dateAttributes)
                    
                    // 绘制描述
                    let descriptionAttributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 16)]
                    let descriptionRect = CGRect(x: 20, y: 50, width: pageRect.width - 40, height: 50)
                    moment.description.draw(in: descriptionRect, withAttributes: descriptionAttributes)
                    
                    // 绘制情绪滑条
                    let sliderX: CGFloat = 20, sliderY: CGFloat = 110
                    let sliderWidth = pageRect.width - 40
                    let sliderHeight: CGFloat = 4
                    let sliderRect = CGRect(x: sliderX, y: sliderY, width: sliderWidth, height: sliderHeight)
                    UIColor.lightGray.setFill()
                    UIBezierPath(roundedRect: sliderRect, cornerRadius: sliderHeight/2).fill()
                    
                    // 绘制情绪标记
                    let markerDiameter: CGFloat = 10
                    let markerX = sliderX + sliderWidth * CGFloat(moment.emotion) - markerDiameter/2
                    let markerY = sliderY - (markerDiameter - sliderHeight)/2
                    let markerRect = CGRect(x: markerX, y: markerY, width: markerDiameter, height: markerDiameter)
                    UIColor.darkGray.setFill()
                    UIBezierPath(ovalIn: markerRect).fill()
                    
                    // 绘制图片（如果一页不足则自动换页）
                    var currentY: CGFloat = sliderY + markerDiameter + 10
                    let bottomMargin: CGFloat = 20
                    for imageData in moment.imageDatas {
                        if let image = UIImage(data: imageData) {
                            let availableWidth = pageRect.width - 40
                            let aspectRatio = image.size.height / image.size.width
                            let imageHeight = availableWidth * aspectRatio
                            
                            if currentY + imageHeight > pageRect.height - bottomMargin {
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
        }
    }
    
    // MARK: - ContentView
    
    struct ContentView: View {
        @StateObject var viewModel = MomentsViewModel()
        @State private var showingAddMoment = false
        @State private var showingShareSheet = false
        @State private var shareItems: [Any] = []
        @State private var selectedImage: UIImage? = nil
        @State private var showingFullScreenImage = false
        
        var body: some View {
            NavigationStack {
                let sortedMoments = viewModel.moments.sorted { $0.date > $1.date }
                List {
                    ForEach(sortedMoments) { moment in
                        NavigationLink {
                            EditMomentView(viewModel: viewModel, moment: moment)
                        } label: {
                            MomentRow(moment: moment, selectedImage: $selectedImage, showingFullScreenImage: $showingFullScreenImage)
                        }
                    }
                    .onDelete { indexSet in
                        let idsToDelete = indexSet.map { sortedMoments[$0].id }
                        viewModel.deleteMoments(matching: idsToDelete)
                    }
                }
                .navigationTitle("Family Moments")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Export PDF") {
                            viewModel.exportPDF { pdfData in
                                if let data = pdfData {
                                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("moments.pdf")
                                    do {
                                        try data.write(to: tempURL)
                                        shareItems = [tempURL]
                                        showingShareSheet = true
                                    } catch {
                                        print("写入 PDF 文件失败: \(error.localizedDescription)")
                                    }
                                }
                            }
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingAddMoment = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .sheet(isPresented: $showingAddMoment) {
                    AddMomentView(viewModel: viewModel)
                }
                .sheet(isPresented: $showingShareSheet) {
                    ActivityView(activityItems: shareItems)
                }
            }
            .fullScreenCover(isPresented: $showingFullScreenImage) {
                FullScreenImageView(image: selectedImage, isPresented: $showingFullScreenImage)
            }
        }
    }
    
    // MARK: - MomentRow
    
    struct MomentRow: View {
        var moment: Moment
        @Binding var selectedImage: UIImage?
        @Binding var showingFullScreenImage: Bool
        
        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                if !moment.imageDatas.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(moment.imageDatas, id: \.self) { data in
                                if let uiImage = UIImage(data: data) {
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
                Text(DateFormatter.momentFormatter.string(from: moment.date))
                    .font(.subheadline)
                    .foregroundColor(.gray)
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
    
    // MARK: - FullScreenImageView
    
    struct FullScreenImageView: View {
        var image: UIImage?
        @Binding var isPresented: Bool
        
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack {
                    Spacer()
                    if let img = image {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .padding()
                    }
                    Spacer()
                    Button("Close") {
                        isPresented = false
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.gray.opacity(0.7))
                    .cornerRadius(8)
                    .padding(.bottom, 40)
                }
            }
        }
    }
    
    // MARK: - AddMomentView
    
    struct AddMomentView: View {
        @Environment(\.dismiss) var dismiss
        @ObservedObject var viewModel: MomentsViewModel
        @State private var description: String = ""
        @State private var selectedImages: [UIImage] = []
        @State private var emotion: Double = 0.5
        @State private var showingImagePicker = false
        
        var body: some View {
            NavigationStack {
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
                            let columns = Array(repeating: GridItem(.flexible()), count: 3)
                            ScrollView {
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
                        Button(action: { showingImagePicker = true }) {
                            Text(selectedImages.isEmpty ? "Choose Photos" : "Add Another")
                        }
                    }
                }
                .navigationTitle("Add Moment")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            let imageDatas = selectedImages.compactMap { $0.jpegData(compressionQuality: 0.8) }
                            viewModel.addMoment(description: description, imageDatas: imageDatas, emotion: emotion)
                            dismiss()
                        }
                        .disabled(description.isEmpty)
                    }
                }
                .sheet(isPresented: $showingImagePicker) {
                    PhotoPicker(selectedImages: $selectedImages)
                }
            }
        }
    }
    
    // MARK: - EditMomentView
    
    struct EditMomentView: View {
        @Environment(\.dismiss) var dismiss
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
            _selectedImages = State(initialValue: moment.imageDatas.compactMap { UIImage(data: $0) })
        }
        
        var body: some View {
            NavigationStack {
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
                            let columns = Array(repeating: GridItem(.flexible()), count: 3)
                            ScrollView {
                                LazyVGrid(columns: columns, spacing: 10) {
                                    ForEach(selectedImages.indices, id: \.self) { index in
                                        ZStack(alignment: .topTrailing) {
                                            Image(uiImage: selectedImages[index])
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 100, height: 100)
                                                .clipped()
                                                .cornerRadius(8)
                                            Button {
                                                selectedImages.remove(at: index)
                                            } label: {
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
                        Button(action: { showingImagePicker = true }) {
                            Text(selectedImages.isEmpty ? "Choose Photos" : "Add Another")
                        }
                    }
                }
                .navigationTitle("Edit Moment")
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Save") {
                            let imageDatas = selectedImages.compactMap { $0.jpegData(compressionQuality: 0.8) }
                            let updatedMoment = Moment(id: moment.id, date: moment.date, description: description, imageDatas: imageDatas, emotion: emotion)
                            viewModel.updateMoment(updatedMoment)
                            dismiss()
                        }
                        .disabled(description.isEmpty)
                    }
                }
                .sheet(isPresented: $showingImagePicker) {
                    PhotoPicker(selectedImages: $selectedImages)
                }
            }
        }
    }
    
    // MARK: - PhotoPicker
    
    struct PhotoPicker: UIViewControllerRepresentable {
        @Binding var selectedImages: [UIImage]
        
        func makeUIViewController(context: Context) -> PHPickerViewController {
            var configuration = PHPickerConfiguration(photoLibrary: .shared())
            configuration.filter = .images
            configuration.selectionLimit = 0  // 0 表示无限制
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = context.coordinator
            return picker
        }
        
        func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) { }
        
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
                        result.itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                            if let error = error {
                                print("加载图片失败: \(error.localizedDescription)")
                                return
                            }
                            if let uiImage = image as? UIImage {
                                DispatchQueue.main.async {
                                    self.parent.selectedImages.append(uiImage)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - ActivityView
    
    struct ActivityView: UIViewControllerRepresentable {
        let activityItems: [Any]
        let applicationActivities: [UIActivity]? = nil
        
        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        }
        
        func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
    }
    
    // MARK: - Preview
    
    struct ContentView_Previews: PreviewProvider {
        static var previews: some View {
            ContentView()
        }
    }
    
