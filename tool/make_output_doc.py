from docx import Document
from docx.shared import Pt
from docx.enum.text import WD_ALIGN_PARAGRAPH

doc = Document()
style = doc.styles['Normal']
style.font.name = 'Calibri'
style.font.size = Pt(11)

doc.add_heading('CUFMAI: Output of the Study', level=0)
doc.add_paragraph('A Footwear Retail Management System with Virtual Fitting Support').alignment = WD_ALIGN_PARAGRAPH.CENTER
doc.add_paragraph('Based on CUFMAI FINALSSS.docx (November 2026) - Chapters 1, 4, 5').alignment = WD_ALIGN_PARAGRAPH.CENTER
doc.add_paragraph('Defense reference - objectives to outputs, modules, and evaluation results.').alignment = WD_ALIGN_PARAGRAPH.CENTER

doc.add_heading('1. What Output of the Study Means in Capstone', level=1)
doc.add_paragraph('In a development-type capstone, the output is the answer to your objectives - what did not exist before and now exists because of the study. Examiners check: You said you will design, develop, test and deploy X. Where is X?')
doc.add_paragraph('For CUFMAI the output has three parts:')
doc.add_paragraph('The system itself (customer, seller, admin + centralized database).', style='List Bullet 2')
doc.add_paragraph('Proof it works (ISO/IEC 25010:2023 + UTAUT results).', style='List Bullet 2')
doc.add_paragraph('Proof it was deployed/accepted (partner store implementation).', style='List Bullet 2')

doc.add_heading('2. Objectives vs Outputs Matrix', level=1)
table = doc.add_table(rows=1, cols=2)
table.style = 'Light Grid Accent 1'
table.rows[0].cells[0].text = 'Objective (Chapter 1)'
table.rows[0].cells[1].text = 'Output (Chapter 4 / 5)'
rows = [
    ('1. Preliminary investigation of partner store', 'Survey of Valladolid Carcar store: manual inventory, manual sales, physical size checks, unorganized custom orders. Ch.3 + PIECES / Cause-and-Effect.'),
    ('2. Analyze data into functional/system requirements', 'Table 1 Use Cases 001-029, non-functional requirements, specs, HIPO, ERD, Use Case diagrams, flowcharts Figs 2-18.'),
    ('3. Design and develop CUFMAI centralized + fitting + customization', 'Flutter app (customer/seller/admin) + React admin-portal + customer-portal + Supabase Postgres/RLS/Auth/Storage/Realtime/Edge Functions. XP method. Figs 39-87.'),
    ('4. Test and evaluate ISO 25010 + UTAUT', 'ISO overall 4.60 Strongly Agree (n=50); UTAUT overall 4.65 Very Highly Accepted (n=50). Tables 8-22.'),
    ('5. Deploy to partner stores', 'Deployment to Valladolid Carcar City (target Dec 2026). Ch.5 Recommendation 2.'),
]
for a, b in rows:
    c = table.add_row().cells
    c[0].text = a
    c[1].text = b

doc.add_heading('3. System Output by Role', level=1)
doc.add_paragraph('Ch.5 p.800: customer can view products, verify size, virtual fitting, order, track, communicate. Seller can manage products/inventory, sales orders, POS. Admin can manage users, review sellers, analyze records, create reports.')
doc.add_heading('3.1 Customer', level=2)
doc.add_paragraph('Browse/view, search/filter, check size availability, virtual fitting 3D preview + AR try-on + foot scan, 5-step customization + special request, store-grouped cart, checkout with voucher Fig.52, Cash/GCash via PayMongo/Card, tracking Placed > Preparing > Ready > Received, history Fig.58, buy-again, follow stores Fig.60, pickup reservation Fig.61, concern filing Fig.62, chat, notifications, 6-digit OTP Fig.41, profile/address book, settings/biometric/MFA.', style='List Bullet')
doc.add_heading('3.2 Seller', level=2)
doc.add_paragraph('Dashboard, product CRUD variants/images, inventory sync, stock management Fig.66, orders + status, custom orders, reservations approve/decline Fig.69, POS cash/GCash/card + barcode + receipt + log Fig.73, vouchers Fig.70, store settings Fig.64, revenue online+POS, reports, reviews Fig.77, messaging.', style='List Bullet')
doc.add_heading('3.3 Admin', level=2)
doc.add_paragraph('User management Fig.44, seller approval Fig.45, product monitoring Fig.78, order monitoring Fig.79, customer data Fig.81, 3D model queue, analytics, security audit Fig.83, notifications Fig.84. Backend Supabase + Edge Functions, 7-area ERD, inventory triggers.', style='List Bullet')

doc.add_heading('4. Evaluation Output', level=1)
doc.add_paragraph('Respondents Table 7: 50 total - 44 Customers (88%), 4 Sellers (8%), 2 IT Experts (4%). ISO 5 = Strongly Agree 4.21-5.00; UTAUT 5 = Very Highly Accepted 4.21-5.00.')
doc.add_heading('4.1 ISO/IEC 25010:2023 - Overall 4.60 Strongly Agree', level=2)
t2 = doc.add_table(rows=1, cols=3)
t2.style = 'Light Grid Accent 1'
t2.rows[0].cells[0].text = 'Characteristic'
t2.rows[0].cells[1].text = 'Weighted Mean'
t2.rows[0].cells[2].text = 'Interpretation'
for name, mean in [('Functional Suitability','4.64'),('Performance Efficiency','4.67'),('Compatibility','4.65'),('Interaction Capability','4.55'),('Reliability','4.65'),('Security','4.65'),('Maintainability','4.58'),('Flexibility','4.65'),('Safety','4.65'),('Overall','4.60')]:
    c = t2.add_row().cells
    c[0].text = name
    c[1].text = mean
    c[2].text = 'Strongly Agree'
doc.add_paragraph('Highest Performance Efficiency 4.67 (fitting without delay 4.82). Lowest Interaction Capability 4.55 (labels clarity 4.40). All nine Strongly Agree Table 17.')

doc.add_heading('4.2 UTAUT - Overall 4.65 Very Highly Accepted', level=2)
t3 = doc.add_table(rows=1, cols=3)
t3.style = 'Light Grid Accent 1'
t3.rows[0].cells[0].text = 'Dimension'
t3.rows[0].cells[1].text = 'Weighted Mean'
t3.rows[0].cells[2].text = 'Interpretation'
for name, mean in [('Performance Expectancy','4.65'),('Effort Expectancy','4.65'),('Social Influence','4.65'),('Facilitating Conditions','4.66'),('Overall','4.65')]:
    c = t3.add_row().cells
    c[0].text = name
    c[1].text = mean
    c[2].text = 'Very Highly Accepted'
doc.add_paragraph('Highest Facilitating Conditions 4.66. All Very Highly Accepted Table 22. Users see CUFMAI as useful, easy, supported, resourced.')

doc.add_heading('5. Conclusion (Chapter 5)', level=1)
doc.add_paragraph('CUFMAI centralizes products, inventory, sales, customers, orders. Customers search, see sizes, preview via fitting. Sellers manage inventory/orders/sales incl. POS. Admins monitor users/products/reports. Limits: needs stable internet; fitting needs AR-capable camera device; lighting/angle affect accuracy; preview is visual only, no exact fit guarantee.')

doc.add_heading('6. Recommendations (Chapter 5)', level=1)
for r in ['1.1 Enhanced virtual fitting with improved size accuracy','1.2 Improved order tracking and notification features','1.3 Enhanced inventory monitoring and sales reporting','1.4 Improved compatibility for different smartphones','2. Full implementation to partner business']:
    doc.add_paragraph(r, style='List Number')

doc.add_heading('7. Defense Script (30 seconds)', level=1)
doc.add_paragraph('The output of our study is a developed and deployed CUFMAI system for customer, seller and admin that centralizes inventory, sales, orders and customer information, with smartphone virtual fitting and customization. It covers all 29 requirements in Table 1, evaluated by 50 respondents with 4.60 Strongly Agree in ISO 25010 and 4.65 Very Highly Accepted in UTAUT, with stated internet and camera/AR limits.')
doc.add_paragraph('Demo flow to prove it: browse > check size > virtual fitting > customize > cart > checkout > seller POS updates inventory > admin sees report. That proves Use Cases 006-025.')

doc.add_paragraph('')
p = doc.add_paragraph('Source: CUFMAI FINALSSS.docx November 2026 Ch.1/4/5 Figs 39-87 Tables 7-22. Generated Nov 2026.')
p.italic = True

out = 'docs/capstone/Output_of_the_Study_CUFMAI.docx'
doc.save(out)
print('saved to ' + out)
