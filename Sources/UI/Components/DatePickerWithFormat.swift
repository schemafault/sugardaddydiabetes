import SwiftUI
import AppKit

struct DatePickerWithFormat: NSViewRepresentable {
    @Binding var date: Date
    
    func makeNSView(context: Context) -> NSDatePicker {
        let datePicker = NSDatePicker()
        
        // Configure the date picker for text field style with 4-digit years
        datePicker.datePickerStyle = .textField
        datePicker.datePickerElements = .yearMonthDay
        datePicker.calendar = Calendar(identifier: .gregorian)
        
        // Create formatter with 4-digit year and set it on the picker
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy" // Explicitly use 4-digit year
        datePicker.formatter = formatter
        
        // Set value
        datePicker.dateValue = date
        
        // Set up delegate to handle changes
        datePicker.target = context.coordinator
        datePicker.action = #selector(Coordinator.dateChanged(_:))
        
        // Set constraints
        datePicker.minDate = Calendar.current.date(from: DateComponents(year: 1900, month: 1, day: 1))
        datePicker.maxDate = Date()
        
        return datePicker
    }
    
    func updateNSView(_ nsView: NSDatePicker, context: Context) {
        nsView.dateValue = date
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: DatePickerWithFormat
        
        init(_ parent: DatePickerWithFormat) {
            self.parent = parent
        }
        
        @objc func dateChanged(_ sender: NSDatePicker) {
            parent.date = sender.dateValue
        }
    }
}

#Preview {
    DatePickerWithFormat(date: .constant(Date()))
        .frame(width: 150, height: 30)
        .padding()
}