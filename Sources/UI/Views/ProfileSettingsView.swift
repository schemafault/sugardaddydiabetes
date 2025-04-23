import SwiftUI

struct ProfileSettingsView: View {
    @EnvironmentObject private var appState: AppState
    
    // Add state for patient profile
    @State private var isEditingPatientProfile = false
    @State private var patientName = ""
    @State private var dateOfBirth: Date = Date()
    @State private var weight = ""
    @State private var weightUnit = "kg"
    @State private var insulinType = ""
    @State private var insulinDose = ""
    @State private var otherMedications = ""
    
    let weightUnits = ["kg", "lbs"]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                patientProfileSection
                
                Spacer()
            }
            .padding()
            .frame(maxWidth: 600, alignment: .center)
        }
        .onAppear {
            loadPatientProfile()
        }
    }
    
    private var patientProfileSection: some View {
        SettingsSection(title: "Patient Information", icon: "person.text.rectangle") {
            if isEditingPatientProfile {
                editProfileView
            } else {
                profileSummaryView
            }
        }
    }
    
    private var profileSummaryView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let profile = appState.patientProfile, let name = profile.name, !name.isEmpty {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 16) {
                        // Profile icon
                        Circle()
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(width: 70, height: 70)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.accentColor)
                            )
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(name)
                                .font(.title3)
                                .fontWeight(.semibold)
                            
                            if let _ = profile.dateOfBirth, let age = profile.formattedAge {
                                HStack {
                                    Image(systemName: "calendar")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                    Text("Age: \(age)")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if let formattedWeight = profile.formattedWeight {
                                HStack {
                                    Image(systemName: "scalemass")
                                        .foregroundColor(.secondary)
                                        .font(.caption)
                                    Text("Weight: \(formattedWeight)")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            isEditingPatientProfile = true
                        }) {
                            Text("Edit")
                                .frame(minWidth: 70)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Medication Information")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        if let insulinType = profile.insulinType, !insulinType.isEmpty {
                            HStack(spacing: 12) {
                                Image(systemName: "cross.case")
                                    .frame(width: 20)
                                    .foregroundColor(.accentColor)
                                
                                VStack(alignment: .leading) {
                                    Text("Insulin Type")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(insulinType)
                                        .font(.body)
                                }
                            }
                            
                            if let insulinDose = profile.insulinDose, !insulinDose.isEmpty {
                                HStack(spacing: 12) {
                                    Image(systemName: "syringe")
                                        .frame(width: 20)
                                        .foregroundColor(.accentColor)
                                    
                                    VStack(alignment: .leading) {
                                        Text("Dosage")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text(insulinDose)
                                            .font(.body)
                                    }
                                }
                            }
                        } else {
                            Text("No insulin information provided")
                                .foregroundColor(.secondary)
                                .font(.body)
                        }
                        
                        if let medications = profile.otherMedications, !medications.isEmpty {
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "pills")
                                        .foregroundColor(.accentColor)
                                    Text("Other Medications")
                                        .font(.headline)
                                }
                                
                                Text(medications)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 4)
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 20) {
                    HStack {
                        Spacer()
                        
                        VStack(spacing: 16) {
                            Image(systemName: "person.fill.questionmark")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            
                            Text("No Patient Profile Yet")
                                .font(.headline)
                                .foregroundColor(.secondary)
                            
                            Text("Add your information to personalize your experience and include it in medical exports.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: 300)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 20)
                    
                    Button(action: {
                        isEditingPatientProfile = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                            Text("Create Patient Profile")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
        }
        .padding()
        .background(Material.thin)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    private var editProfileView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Personal Information Section
            VStack(alignment: .leading, spacing: 15) {
                Text("Personal Information")
                    .font(.headline)
                    .padding(.bottom, 5)
                
                VStack(alignment: .leading, spacing: 15) {
                    inputField(title: "Name", binding: $patientName, placeholder: "Full name", systemImage: "person.fill")
                    
                    dateField(title: "Date of Birth", date: $dateOfBirth, systemImage: "calendar")
                    
                    weightField(title: "Weight", weight: $weight, unit: $weightUnit, systemImage: "scalemass")
                }
            }
            
            Divider()
            
            // Medication Information Section
            VStack(alignment: .leading, spacing: 15) {
                Text("Medication Information")
                    .font(.headline)
                    .padding(.bottom, 5)
                
                VStack(alignment: .leading, spacing: 15) {
                    inputField(title: "Insulin Type", binding: $insulinType, placeholder: "e.g., Humalog, Lantus", systemImage: "cross.case")
                    
                    inputField(title: "Insulin Dose", binding: $insulinDose, placeholder: "e.g., 10 units morning, 8 units evening", systemImage: "syringe")
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "pills")
                                .frame(width: 24)
                                .foregroundColor(.secondary)
                            Text("Other Medications")
                                .font(.subheadline)
                        }
                        
                        TextEditor(text: $otherMedications)
                            .frame(minHeight: 100)
                            .padding(8)
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
            }
            
            // Action Buttons
            HStack {
                Button("Cancel") {
                    isEditingPatientProfile = false
                    loadPatientProfile()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Save Profile") {
                    savePatientProfile()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
                .disabled(patientName.isEmpty)
            }
            .padding(.top, 10)
        }
        .padding()
        .background(Material.thin)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // Helper views for form fields
    private func inputField(title: String, binding: Binding<String>, placeholder: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .frame(width: 24)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.subheadline)
            }
            
            TextField(placeholder, text: binding)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.leading, 24)
        }
    }
    
    private func dateField(title: String, date: Binding<Date>, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .frame(width: 24)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.subheadline)
            }
            
            DatePickerWithFormat(date: date)
                .frame(height: 28)
                .padding(.leading, 24)
        }
    }
    
    private func weightField(title: String, weight: Binding<String>, unit: Binding<String>, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: systemImage)
                    .frame(width: 24)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.subheadline)
            }
            
            HStack {
                TextField("Weight", text: weight)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                Picker("Unit", selection: unit) {
                    ForEach(weightUnits, id: \.self) { unit in
                        Text(unit).tag(unit)
                    }
                }
                .frame(width: 80)
            }
            .padding(.leading, 24)
        }
    }
    
    // Load patient profile data into state variables
    private func loadPatientProfile() {
        if let profile = appState.patientProfile {
            patientName = profile.name ?? ""
            
            if let dob = profile.dateOfBirth {
                dateOfBirth = dob
            } else {
                // Default to a reasonable birth date if none is set
                let defaultDate = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
                dateOfBirth = defaultDate
            }
            
            // Handle optional Double value with nil coalescing
            weight = (profile.weight ?? 0) > 0 ? String(profile.weight ?? 0) : ""
            
            weightUnit = profile.weightUnit ?? "kg"
            insulinType = profile.insulinType ?? ""
            insulinDose = profile.insulinDose ?? ""
            otherMedications = profile.otherMedications ?? ""
        } else {
            // Initialize with reasonable defaults
            let defaultDate = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
            dateOfBirth = defaultDate
        }
    }
    
    // Save patient profile data
    private func savePatientProfile() {
        var weightValue: Double?
        if let doubleWeight = Double(weight) {
            weightValue = doubleWeight
        }
        
        appState.updatePatientProfile(
            name: patientName,
            dateOfBirth: dateOfBirth,
            weight: weightValue,
            weightUnit: weightUnit,
            insulinType: insulinType,
            insulinDose: insulinDose,
            otherMedications: otherMedications
        )
        
        isEditingPatientProfile = false
    }
}

#Preview {
    ProfileSettingsView()
        .environmentObject(AppState())
}