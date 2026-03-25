import SwiftUI
import SwiftData
import PhotosUI

struct AddEditMemberView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // 编辑模式：传入已有成员则为编辑，否则为新增
    let member: Member?

    // MARK: - 表单字段

    @State private var name = ""
    @State private var birthday: Date = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var hasBirthday = false
    @State private var gender: Gender = .male
    @State private var bloodType: BloodType = .unknown
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var notes = ""

    // 健康状况
    @State private var allergiesText = ""       // 逗号分隔
    @State private var conditionsText = ""      // 逗号分隔
    @State private var healthNotes = ""

    // 头像
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var avatarData: Data?

    // 校验
    @State private var showingValidationError = false
    @State private var validationMessage = ""

    // MARK: - Init

    init(member: Member? = nil) {
        self.member = member
    }

    var isEditing: Bool { member != nil }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                avatarSection
                basicInfoSection
                bodyMetricsSection
                healthStatusSection
                notesSection
            }
            .navigationTitle(isEditing ? "编辑成员" : "添加成员")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "保存" : "添加") { saveAction() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { populateFields() }
            .alert("请检查输入", isPresented: $showingValidationError) {
                Button("好的") {}
            } message: {
                Text(validationMessage)
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    avatarData = try? await newItem?.loadTransferable(type: Data.self)
                }
            }
        }
    }

    // MARK: - 表单区块

    private var avatarSection: some View {
        Section {
            HStack {
                Spacer()
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        avatarPreview
                            .frame(width: 90, height: 90)

                        Image(systemName: "camera.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, .blue)
                            .offset(x: 4, y: 4)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel("选择头像")
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    private var basicInfoSection: some View {
        Section("基本信息") {
            HStack {
                Text("姓名")
                Spacer()
                TextField("请输入姓名", text: $name)
                    .multilineTextAlignment(.trailing)
            }

            Picker("性别", selection: $gender) {
                ForEach(Gender.allCases, id: \.self) { g in
                    Text(g.displayName).tag(g)
                }
            }

            Toggle("设置生日", isOn: $hasBirthday)

            if hasBirthday {
                DatePicker(
                    "生日",
                    selection: $birthday,
                    in: ...Date(),
                    displayedComponents: .date
                )
            }

            Picker("血型", selection: $bloodType) {
                ForEach(BloodType.allCases, id: \.self) { bt in
                    Text(bt.rawValue).tag(bt)
                }
            }
        }
    }

    private var bodyMetricsSection: some View {
        Section("身体数据") {
            HStack {
                Text("身高")
                Spacer()
                TextField("厘米", text: $heightText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("cm").foregroundStyle(.secondary)
            }

            HStack {
                Text("体重")
                Spacer()
                TextField("公斤", text: $weightText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("kg").foregroundStyle(.secondary)
            }
        }
    }

    private var healthStatusSection: some View {
        Section("健康状况") {
            VStack(alignment: .leading, spacing: 4) {
                Text("过敏原")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("如：青霉素、花粉（用逗号分隔）", text: $allergiesText)
                    .font(.callout)
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("慢性病 / 长期病史")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("如：高血压、糖尿病（用逗号分隔）", text: $conditionsText)
                    .font(.callout)
            }
            .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("当前健康说明")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("简要描述当前健康状况...", text: $healthNotes, axis: .vertical)
                    .font(.callout)
                    .lineLimit(3, reservesSpace: true)
            }
            .padding(.vertical, 2)
        }
    }

    private var notesSection: some View {
        Section("备注") {
            TextField("其他备注信息...", text: $notes, axis: .vertical)
                .lineLimit(3, reservesSpace: true)
        }
    }

    // MARK: - 头像预览

    @ViewBuilder
    private var avatarPreview: some View {
        if let data = avatarData ?? member?.avatarData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
        } else {
            Circle()
                .fill(gender == .female ? Color.pink : .blue)
                .overlay {
                    Text(name.isEmpty ? "?" : String(name.prefix(1)))
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                }
        }
    }

    // MARK: - 逻辑

    private func populateFields() {
        guard let m = member else { return }
        name = m.name
        gender = m.gender
        bloodType = m.bloodType
        hasBirthday = m.birthday != nil
        birthday = m.birthday ?? Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
        heightText = m.heightCm.map { "\(Int($0))" } ?? ""
        weightText = m.weightKg.map { "\(Int($0))" } ?? ""
        notes = m.notes
        allergiesText = m.allergies.joined(separator: "、")
        conditionsText = m.chronicConditions.joined(separator: "、")
        healthNotes = m.currentHealthNotes
        avatarData = m.avatarData
    }

    private func saveAction() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            validationMessage = "请输入成员姓名"
            showingValidationError = true
            return
        }

        if let m = member {
            // 编辑现有成员
            m.name = trimmedName
            m.gender = gender
            m.bloodType = bloodType
            m.birthday = hasBirthday ? birthday : nil
            m.heightCm = Double(heightText.replacingOccurrences(of: ",", with: "."))
            m.weightKg = Double(weightText.replacingOccurrences(of: ",", with: "."))
            m.notes = notes
            m.allergies = parseCommaList(allergiesText)
            m.chronicConditions = parseCommaList(conditionsText)
            m.currentHealthNotes = healthNotes
            if let data = avatarData { m.avatarData = data }
            m.updatedAt = Date()
        } else {
            // 新增成员
            let newMember = Member(name: trimmedName, gender: gender, bloodType: bloodType)
            newMember.birthday = hasBirthday ? birthday : nil
            newMember.heightCm = Double(heightText.replacingOccurrences(of: ",", with: "."))
            newMember.weightKg = Double(weightText.replacingOccurrences(of: ",", with: "."))
            newMember.notes = notes
            newMember.allergies = parseCommaList(allergiesText)
            newMember.chronicConditions = parseCommaList(conditionsText)
            newMember.currentHealthNotes = healthNotes
            newMember.avatarData = avatarData
            modelContext.insert(newMember)
        }

        dismiss()
    }

    /// 将逗号/顿号分隔的字符串解析为标签数组
    private func parseCommaList(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet(charactersIn: ",，、"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Preview

#Preview("新增成员") {
    AddEditMemberView()
        .modelContainer(MockData.previewContainer)
}

#Preview("编辑成员") {
    AddEditMemberView(member: MockData.sampleMember)
        .modelContainer(MockData.previewContainer)
}
