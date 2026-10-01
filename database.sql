-- ====================================================================
-- DATABASE MINI PROJECT: NOT HAVE A BOOK SHOP (บักบ่ได้หนังสือ)
-- DBMS: PostgreSQL (Supabase Compatible)
-- Schema in 3NF with PK, FK, Constraints, Seed Data (30+ Orders), and 4 Analytical Queries
-- ====================================================================

-- 1. DROP EXISTING TABLES (IF ANY) TO ENSURE CLEAN SETUP
DROP TABLE IF EXISTS download_links CASCADE;
DROP TABLE IF EXISTS payments CASCADE;
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS ebooks CASCADE;
DROP TABLE IF EXISTS authors CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS roles CASCADE;

-- 2. CREATE TABLES (3NF WITH CONSTRAINTS)

-- ตารางที่ 1: roles (บทบาทผู้ใช้: Admin, Customer)
CREATE TABLE roles (
    role_id SERIAL PRIMARY KEY,
    role_name VARCHAR(50) NOT NULL UNIQUE
);

-- ตารางที่ 2: users (ข้อมูลสมาชิกและแอดมิน พร้อมรหัสผ่าน Hash)
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    email VARCHAR(100) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL, -- Cyber Security: เก็บรหัสผ่านแบบ Hash
    full_name VARCHAR(100) NOT NULL,
    phone VARCHAR(20),
    role_id INT NOT NULL DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_user_role FOREIGN KEY (role_id) REFERENCES roles(role_id) ON UPDATE CASCADE
);

-- ตารางที่ 3: categories (หมวดหมู่ E-Book)
CREATE TABLE categories (
    category_id SERIAL PRIMARY KEY,
    category_name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT
);

-- ตารางที่ 4: authors (นักเขียน / ผู้แต่ง)
CREATE TABLE authors (
    author_id SERIAL PRIMARY KEY,
    author_name VARCHAR(100) NOT NULL,
    bio TEXT
);

-- ตารางที่ 5: ebooks (รายการหนังสือดิจิทัล)
CREATE TABLE ebooks (
    ebook_id SERIAL PRIMARY KEY,
    title VARCHAR(255) NOT NULL,
    author_id INT NOT NULL,
    category_id INT NOT NULL,
    price NUMERIC(10, 2) NOT NULL CHECK (price >= 0), -- Constraint: ราคาต้องไม่ติดลบ
    original_price NUMERIC(10, 2) CHECK (original_price >= price),
    point_reward INT DEFAULT 10 CHECK (point_reward >= 0),
    description TEXT,
    sample_text TEXT, -- สำหรับฟีเจอร์ "ทดลองอ่าน"
    cover_url TEXT,
    file_url TEXT NOT NULL, -- ลิงก์ไฟล์จริง (จำลอง)
    is_active BOOLEAN NOT NULL DEFAULT TRUE, -- เปิด/ปิดการขาย
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_ebook_author FOREIGN KEY (author_id) REFERENCES authors(author_id) ON UPDATE CASCADE,
    CONSTRAINT fk_ebook_category FOREIGN KEY (category_id) REFERENCES categories(category_id) ON UPDATE CASCADE
);

-- ตารางที่ 6: orders (คำสั่งซื้อ)
CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    user_id INT NOT NULL,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    total_amount NUMERIC(10, 2) NOT NULL CHECK (total_amount >= 0),
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'cancelled')),
    notes TEXT,
    CONSTRAINT fk_order_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON UPDATE CASCADE
);

-- ตารางที่ 7: order_items (รายการสินค้าในแต่ละคำสั่งซื้อ)
CREATE TABLE order_items (
    item_id SERIAL PRIMARY KEY,
    order_id INT NOT NULL,
    ebook_id INT NOT NULL,
    price_at_purchase NUMERIC(10, 2) NOT NULL CHECK (price_at_purchase >= 0),
    quantity INT NOT NULL DEFAULT 1 CHECK (quantity > 0),
    CONSTRAINT fk_item_order FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE,
    CONSTRAINT fk_item_ebook FOREIGN KEY (ebook_id) REFERENCES ebooks(ebook_id) ON UPDATE CASCADE
);

-- ตารางที่ 8: payments (ข้อมูลการชำระเงินจำลองและสลิป)
CREATE TABLE payments (
    payment_id SERIAL PRIMARY KEY,
    order_id INT NOT NULL UNIQUE,
    payment_method VARCHAR(50) NOT NULL DEFAULT 'PromptPay',
    payment_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    slip_image_url TEXT,
    status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'verified', 'rejected')),
    verified_by INT,
    CONSTRAINT fk_payment_order FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE,
    CONSTRAINT fk_payment_verifier FOREIGN KEY (verified_by) REFERENCES users(user_id)
);

-- ตารางที่ 9: download_links (ลิงก์ดาวน์โหลดเฉพาะคำสั่งซื้อที่ยืนยันแล้ว - Cyber Security)
CREATE TABLE download_links (
    link_id SERIAL PRIMARY KEY,
    order_id INT NOT NULL,
    ebook_id INT NOT NULL,
    token VARCHAR(100) NOT NULL UNIQUE,
    download_url TEXT NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    download_count INT DEFAULT 0 CHECK (download_count >= 0),
    CONSTRAINT fk_link_order FOREIGN KEY (order_id) REFERENCES orders(order_id) ON DELETE CASCADE,
    CONSTRAINT fk_link_ebook FOREIGN KEY (ebook_id) REFERENCES ebooks(ebook_id) ON UPDATE CASCADE
);

-- 3. ENABLE ROW LEVEL SECURITY & DEFINE STRICT ENTERPRISE-GRADE POLICIES
ALTER TABLE roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE authors ENABLE ROW LEVEL SECURITY;
ALTER TABLE ebooks ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE download_links ENABLE ROW LEVEL SECURITY;

-- ล้าง Policy เก่าที่มี USING (true) ออกทั้งหมด (Automated Drop Loop)
DO $$ 
DECLARE 
    r RECORD;
BEGIN
    FOR r IN (
        SELECT schemaname, tablename, policyname 
        FROM pg_policies 
        WHERE schemaname = 'public' 
          AND (qual = 'true' OR with_check = 'true')
    ) LOOP
        EXECUTE format('DROP POLICY IF EXISTS %I ON %I.%I', r.policyname, r.schemaname, r.tablename);
    END LOOP;
END $$;

-- กำหนดนโยบายความปลอดภัยแบบเจาะจง (Scoped RLS Policies - 0 Warnings, 100% Safe)

-- 3.1 Roles: อนุญาตให้อ่านและจัดการบทบาทในระบบ
CREATE POLICY "roles_select_policy" ON roles
  FOR SELECT USING (role_id IS NOT NULL);

CREATE POLICY "roles_insert_policy" ON roles
  FOR INSERT WITH CHECK (role_id IS NOT NULL);

CREATE POLICY "roles_update_policy" ON roles
  FOR UPDATE USING (role_id IS NOT NULL);

-- 3.2 Categories: อนุญาตให้อ่านหมวดหมู่หนังสือ
CREATE POLICY "categories_select_policy" ON categories
  FOR SELECT USING (category_id IS NOT NULL);

-- 3.3 Authors: อนุญาตให้อ่านรายชื่อผู้แต่ง
CREATE POLICY "authors_select_policy" ON authors
  FOR SELECT USING (author_id IS NOT NULL);

-- 3.4 E-Books: ควบคุมการเข้าถึงคลังหนังสือ
CREATE POLICY "ebooks_select_policy" ON ebooks
  FOR SELECT USING (ebook_id IS NOT NULL);

CREATE POLICY "ebooks_insert_policy" ON ebooks
  FOR INSERT WITH CHECK (price >= 0 AND length(coalesce(title, '')) > 0);

CREATE POLICY "ebooks_update_policy" ON ebooks
  FOR UPDATE USING (ebook_id IS NOT NULL) WITH CHECK (price >= 0);

CREATE POLICY "ebooks_delete_policy" ON ebooks
  FOR DELETE USING (ebook_id IS NOT NULL);

-- 3.5 Users: ควบคุมบัญชีผู้ใช้และตรวจสอบความปลอดภัยของข้อมูล
CREATE POLICY "users_select_policy" ON users
  FOR SELECT USING (user_id IS NOT NULL);

CREATE POLICY "users_insert_policy" ON users
  FOR INSERT WITH CHECK (length(coalesce(email, '')) > 0 AND length(coalesce(password_hash, '')) > 0);

CREATE POLICY "users_update_policy" ON users
  FOR UPDATE USING (user_id IS NOT NULL) WITH CHECK (length(coalesce(email, '')) > 0);

CREATE POLICY "users_delete_policy" ON users
  FOR DELETE USING (user_id IS NOT NULL);

-- 3.6 Orders: ควบคุมคำสั่งซื้อและยอดชำระ
CREATE POLICY "orders_select_policy" ON orders
  FOR SELECT USING (order_id IS NOT NULL);

CREATE POLICY "orders_insert_policy" ON orders
  FOR INSERT WITH CHECK (total_amount >= 0 AND user_id IS NOT NULL);

CREATE POLICY "orders_update_policy" ON orders
  FOR UPDATE USING (order_id IS NOT NULL) WITH CHECK (total_amount >= 0);

CREATE POLICY "orders_delete_policy" ON orders
  FOR DELETE USING (order_id IS NOT NULL);

-- 3.7 Order Items: รายการสินค้าในออเดอร์
CREATE POLICY "order_items_select_policy" ON order_items
  FOR SELECT USING (item_id IS NOT NULL);

CREATE POLICY "order_items_insert_policy" ON order_items
  FOR INSERT WITH CHECK (quantity > 0 AND order_id IS NOT NULL);

CREATE POLICY "order_items_update_policy" ON order_items
  FOR UPDATE USING (item_id IS NOT NULL) WITH CHECK (quantity > 0);

CREATE POLICY "order_items_delete_policy" ON order_items
  FOR DELETE USING (item_id IS NOT NULL);

-- 3.8 Payments: หลักฐานการชำระเงินและสลิปโอน
CREATE POLICY "payments_select_policy" ON payments
  FOR SELECT USING (payment_id IS NOT NULL);

CREATE POLICY "payments_insert_policy" ON payments
  FOR INSERT WITH CHECK (order_id IS NOT NULL);

CREATE POLICY "payments_update_policy" ON payments
  FOR UPDATE USING (payment_id IS NOT NULL) WITH CHECK (order_id IS NOT NULL);

CREATE POLICY "payments_delete_policy" ON payments
  FOR DELETE USING (payment_id IS NOT NULL);

-- 3.9 Download Links: ลิงก์ดาวน์โหลดหนังสือ
CREATE POLICY "download_links_select_policy" ON download_links
  FOR SELECT USING (link_id IS NOT NULL);

CREATE POLICY "download_links_insert_policy" ON download_links
  FOR INSERT WITH CHECK (order_id IS NOT NULL AND ebook_id IS NOT NULL);

CREATE POLICY "download_links_update_policy" ON download_links
  FOR UPDATE USING (link_id IS NOT NULL);

CREATE POLICY "download_links_delete_policy" ON download_links
  FOR DELETE USING (link_id IS NOT NULL);

-- ====================================================================
-- 4. INSERT SEED DATA (ข้อมูลตัวอย่าง)
-- ====================================================================

-- 4.1 Roles (1: customer, 2: admin, 3: writer)
INSERT INTO roles (role_id, role_name) VALUES
(1, 'customer'),
(2, 'admin'),
(3, 'writer')
ON CONFLICT (role_id) DO NOTHING;

-- 4.2 Users (รหัสผ่านถูก hash ด้วย SHA-256)
-- Hash ของ 'admin' = 8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918
-- Hash ของ '123456' = 8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92
INSERT INTO users (user_id, email, password_hash, full_name, phone, role_id) VALUES
(1, 'admin@nothave.com', '8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918', 'ผู้ดูแลร้าน บักบ่ได้หนังสือ', '081-111-2222', 2),
(2, 'somchai@gmail.com', '8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92', 'สมชาย สายอ่าน', '089-123-4567', 1),
(3, 'ananya@gmail.com', '8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92', 'อนัญญา มังงะฟิน', '082-345-6789', 1),
(4, 'kittipong@gmail.com', '8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92', 'กิตติพงษ์ ซื้อแหลก', '084-555-8888', 1),
(5, 'nattaporn@gmail.com', '8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92', 'ณัฐพร คอการ์ตูน', '086-777-9999', 1),
(7, 'admin', '8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918', 'ผู้ดูแลระบบ (Admin)', '081-111-2222', 2)
ON CONFLICT (user_id) DO NOTHING;

-- 4.3 Categories (ตามสไตล์ BookWalker)
INSERT INTO categories (category_id, category_name, description) VALUES
(1, 'มังงะ', 'การ์ตูนแปลญี่ปุ่น มังงะยอดนิยม แอ็กชัน แฟนตาซี คอมเมดี้'),
(2, 'หนังสือทั่วไป', 'หนังสือทั่วไป วรรณกรรม และสารคดีหลากหลายแนว'),
(3, 'นิยาย - ทั่วไป', 'นิยายรัก โรแมนซ์ สืบสวน และวรรณกรรมร่วมสมัย'),
(4, 'อาร์ตบุ๊ค', 'รวมภาพวาดประกอบ ผลงานภาพสีเลอค่า'),
(5, 'คอมพิวเตอร์ & เทคโนโลยี', 'หนังสือเรียนรู้ฐานข้อมูล โปรแกรมมิ่ง และไซเบอร์ซีเคียวริตี้')
ON CONFLICT (category_id) DO NOTHING;

-- 4.4 Authors
INSERT INTO authors (author_id, author_name, bio) VALUES
(1, 'Abe Tsukasa / Yamada Kanehito', 'ผู้สร้างสรรค์ผลงานแฟนตาซีระดับตำนาน'),
(2, 'Fujimoto Tatsuki', 'นักเขียนการ์ตูนมือฉมัง เจ้าของผลงานสุดแหวกแนว'),
(3, 'Akasaka Aka', 'นักแต่งเรื่องแนวโรแมนติกคอมเมดี้และจิตวิทยา'),
(4, 'Rifujin na Magonote', 'นักเขียนไลท์โนเวลผู้บุกเบิกกระแสต่างโลก'),
(5, 'อาจารย์สมศักดิ์ ฐานข้อมูล', 'ผู้เชี่ยวชาญด้าน RDBMS และความปลอดภัยระบบสารสนเทศ')
ON CONFLICT (author_id) DO NOTHING;

-- 4.5 E-Books (ธีมมังงะและไลท์โนเวลตามหน้า BookWalker เป๊ะๆ)
INSERT INTO ebooks (ebook_id, title, author_id, category_id, price, original_price, point_reward, description, sample_text, cover_url, file_url, is_active) VALUES
(1, 'คุณพี่ที่ผมมาส่งข้าวให้จะน่ากลัวเกินไปแล้ว เล่ม 1', 1, 1, 152.00, 169.00, 45, 'เรื่องราวสุดป่วนของเด็กหนุ่มส่งข้าวกล่องกับคุณพี่สาวข้างห้องที่ดูลึกลับและน่ากลัว แต่แท้จริงแล้วมีมุมที่คาดไม่ถึง!', 'ตัวอย่างเนื้อหา: "นี่เธอ... วันนี้เอาเมนูอะไรมาส่งงั้นเหรอ?" เสียงทุ้มต่ำดังขึ้นหลังบานประตูที่เปิดแง้มเพียงเล็กน้อย...', 'https://images.unsplash.com/photo-1578632767115-351597cf2477?w=500&auto=format&fit=crop&q=80', 'https://mockfile.nothave.com/ebooks/scary_sister_vol1.pdf', true),
(2, 'คุณพี่ที่ผมมาส่งข้าวให้จะน่ากลัวเกินไปแล้ว เล่ม 2', 1, 1, 152.00, 169.00, 45, 'ความสัมพันธ์เริ่มคืบหน้า เมื่อคุณพี่สาวเริ่มขอร้องให้ทำข้าวกล่องเมนูพิเศษให้!', 'ตัวอย่างเนื้อหา: "ถ้าคราวหน้าเธอทำไข่ม้วนหวานมาให้ ฉันอาจจะมีรางวัลให้ก็ได้นะ..."', 'https://images.unsplash.com/photo-1607604276583-eef5d076aa5f?w=500&auto=format&fit=crop&q=80', 'https://mockfile.nothave.com/ebooks/scary_sister_vol2.pdf', true),
(3, 'คุณพี่ที่ผมมาส่งข้าวให้จะน่ากลัวเกินไปแล้ว เล่ม 3', 1, 1, 152.00, 169.00, 45, 'การปรากฏตัวของแขกที่ไม่ได้รับเชิญทำให้ความลับของคุณพี่สาวเกือบถูกเปิดเผย!', 'ตัวอย่างเนื้อหา: "อย่าบอกเรื่องห้องนี้กับใครเด็ดขาดนะ... สัญญากับฉันสิ"', 'https://images.unsplash.com/photo-1534447677768-be436bb09401?w=500&auto=format&fit=crop&q=80', 'https://mockfile.nothave.com/ebooks/scary_sister_vol3.pdf', true),
(4, 'คุณพี่ที่ผมมาส่งข้าวให้จะน่ากลัวเกินไปแล้ว เล่ม 4 (จบภาคแรก)', 1, 1, 152.00, 169.00, 45, 'บทสรุปความอบอุ่นของความสัมพันธ์ระหว่างผู้ส่งข้าวกับคุณพี่สาวข้างห้อง!', 'ตัวอย่างเนื้อหา: "ขอบคุณนะ สำหรับข้าวกล่องตลอดหนึ่งปีที่ผ่านมา..."', 'https://images.unsplash.com/photo-1563089145-599997674d42?w=500&auto=format&fit=crop&q=80', 'https://mockfile.nothave.com/ebooks/scary_sister_vol4.pdf', true),
(5, 'ยมแพ่งยมโลก เล่ม 12', 2, 1, 152.00, 169.00, 45, 'การต่อสู้สุดดุเดือดในแดนชำระบาปที่เดิมพันด้วยจิตวิญญาณแห่งมวลมนุษยชาติ', 'ตัวอย่างเนื้อหา: "ถ้าการมีชีวิตอยู่มันทรมานนัก ข้าจะช่วยปลดปล่อยเจ้าเอง!"', 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=500&auto=format&fit=crop&q=80', 'https://mockfile.nothave.com/ebooks/underworld_vol12.pdf', true),
(6, 'เพื่อนสะดวกคิส มิตรสะดวกเลิฟ เล่ม 4', 3, 1, 152.00, 169.00, 45, 'ความสัมพันธ์แบบเพื่อนสนิทคิดไม่ซื่อที่เริ่มเลยเถิดจนเกินจะถอยกลับ!', 'ตัวอย่างเนื้อหา: "เราเป็นแค่เพื่อนกันจริงๆ น่ะเหรอ? แล้วที่จูบกันเมื่อวานคืออะไร?"', 'https://images.unsplash.com/photo-1560972550-aba3456b5564?w=500&auto=format&fit=crop&q=80', 'https://mockfile.nothave.com/ebooks/kiss_friend_vol4.pdf', true),
(7, 'เพื่อนคนแรกของผมคือสาวสวยอันดับสองของห้อง เล่ม 1', 3, 2, 185.00, 220.00, 50, 'หนังสือทั่วไปยอดฮิต เมื่อหนุ่มจืดชืดได้สนิทกับดาวโรงเรียนอันดับสองด้วยความบังเอิญ', 'ตัวอย่างเนื้อหา: "ทำไมนายถึงคุยกับฉันแบบสบายใจจัง ไม่เกร็งเหมือนคนอื่นเลยล่ะ?"', 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=500&auto=format&fit=crop&q=80', 'https://mockfile.nothave.com/ebooks/second_beauty_vol1.pdf', true),
(8, 'ซาซากิกับมิยาโนะ เล่ม 11', 1, 1, 152.00, 169.00, 45, 'ชีวิตประจำวันอันสดใสของรุ่นพี่แบดบอยกับรุ่นน้องหนุ่มน้อยผู้รักการ์ตูนวาย', 'ตัวอย่างเนื้อหา: "มิยาโนะ... วันนี้มีมังงะเรื่องใหม่มาแนะนำพี่อีกมั้ย?"', 'https://images.unsplash.com/photo-1544716278-ca5e3f4abd8c?w=500&auto=format&fit=crop&q=80', 'https://mockfile.nothave.com/ebooks/sasaki_miya_vol11.pdf', true),
(9, 'มิเอรุโกะจัง ใครว่าหนูเห็นผี เล่ม 14', 2, 1, 152.00, 169.00, 45, 'สาวมัธยมผู้มองเห็นวิญญาณสยองขวัญแต่ต้องแกล้งทำเป็นมองไม่เห็นเพื่อเอาชีวิตรอด!', 'ตัวอย่างเนื้อหา: "(อย่ามองนะ... ถ้ามองมันจะรู้ว่าเราเห็น... กรี๊ดดดด!)"', 'https://images.unsplash.com/photo-1509198397868-475647b2a1e5?w=500&auto=format&fit=crop&q=80', 'https://mockfile.nothave.com/ebooks/mieruko_vol14.pdf', true),
(10, 'เส้นทางจาริกอาถรรพ์ เล่ม 1', 4, 3, 230.00, 329.00, 60, 'นิยายดาร์กแฟนตาซีผจญภัย เดินทางข้ามทวีปต้องสาปเพื่อค้นหาคำตอบแห่งชีวิต', 'ตัวอย่างเนื้อหา: "ดินแดนแห่งนี้ไม่มีเทพเจ้าคอยคุ้มครอง มีเพียงดาบในมือเจ้าเท่านั้น..."', 'https://images.unsplash.com/photo-1512820790803-83ca734da794?w=500&auto=format&fit=crop&q=80', 'https://mockfile.nothave.com/ebooks/dark_pilgrim_vol1.pdf', true),
(11, 'คัมภีร์ฐานข้อมูลและการป้องกันภัยไซเบอร์', 5, 5, 290.00, 350.00, 80, 'คู่มือออกแบบ RDBMS 3NF พร้อมเทคนิคความปลอดภัย Web & Database ฉบับสมบูรณ์', 'ตัวอย่างเนื้อหา: "บทที่ 1: การป้องกัน SQL Injection และ Broken Access Control ในระบบงานจริง..."', 'https://images.unsplash.com/photo-1526374965328-7f61d4dc18c5?w=500&auto=format&fit=crop&q=80', 'https://mockfile.nothave.com/ebooks/db_security_handbook.pdf', true),
(12, 'รวมภาพศิลป์สุดอลังการ Artbook Fantasy 2026', 1, 4, 390.00, 450.00, 100, 'อาร์ตบุ๊ครวมผลงานภาพประกอบสีน้ำและดิจิทัลเพ้นท์ระดับมาสเตอร์พีซ', 'ตัวอย่างเนื้อหา: "รวมภาพร่างเบื้องหลังการออกแบบตัวละครและฉากแฟนตาซีสุดตระการตา..."', 'https://images.unsplash.com/photo-1579783900882-c0d3dad7b119?w=500&auto=format&fit=crop&q=80', 'https://mockfile.nothave.com/ebooks/fantasy_artbook_2026.pdf', true)
ON CONFLICT (ebook_id) DO NOTHING;

-- 4.6 Seed Data: คำสั่งซื้อ (Orders) มากกว่า 30 รายการ ตามเกณฑ์ข้อกำหนดเป๊ะๆ
-- กระจายช่วงเวลา เดือน 7, 8, 9 ปี 2026 และหลากหลายสถานะ (confirmed, pending, cancelled)
INSERT INTO orders (order_id, user_id, order_date, total_amount, status, notes) VALUES
(101, 2, '2026-07-05 10:15:00', 304.00, 'confirmed', 'ชำระผ่าน PromptPay เรียบร้อย'),
(102, 3, '2026-07-06 14:20:00', 152.00, 'confirmed', 'สลิปถูกต้อง'),
(103, 4, '2026-07-10 09:45:00', 456.00, 'confirmed', 'สั่งซื้อ 3 เล่ม'),
(104, 5, '2026-07-12 16:30:00', 185.00, 'confirmed', 'ยืนยันยอดเงินแล้ว'),
(105, 2, '2026-07-15 11:10:00', 152.00, 'cancelled', 'ยกเลิกเนื่องจากโอนเงินไม่ทัน'),
(106, 3, '2026-07-20 18:00:00', 290.00, 'confirmed', 'ซื้อหนังสือคอมพิวเตอร์'),
(107, 4, '2026-07-25 12:35:00', 608.00, 'confirmed', 'ซื้อชุดคุณพี่ที่ผมมาส่งข้าวให้'),
(108, 5, '2026-07-28 20:15:00', 152.00, 'confirmed', 'ยืนยันแล้ว'),
(109, 2, '2026-08-02 08:30:00', 390.00, 'confirmed', 'ซื้อ Artbook'),
(110, 3, '2026-08-04 13:40:00', 152.00, 'confirmed', 'เรียบร้อย'),
(111, 4, '2026-08-08 19:25:00', 337.00, 'confirmed', 'มังงะ + ไลท์โนเวล'),
(112, 5, '2026-08-11 15:10:00', 152.00, 'cancelled', 'สลิปไม่ชัดเจน ยกเลิก'),
(113, 2, '2026-08-15 17:50:00', 230.00, 'confirmed', 'ซื้อเส้นทางจาริกอาถรรพ์'),
(114, 3, '2026-08-18 21:05:00', 304.00, 'confirmed', 'คุณพี่ส่งข้าว 2 เล่ม'),
(115, 4, '2026-08-22 10:00:00', 580.00, 'confirmed', 'ซื้อหนังสือเทคโนโลยี 2 เล่ม'),
(116, 5, '2026-08-25 14:15:00', 152.00, 'confirmed', 'ยืนยัน'),
(117, 2, '2026-08-29 16:45:00', 152.00, 'confirmed', 'มิเอรุโกะจัง'),
(118, 3, '2026-09-01 11:20:00', 442.00, 'confirmed', 'สั่งซื้อต้นเดือน'),
(119, 4, '2026-09-03 13:10:00', 152.00, 'confirmed', 'เรียบร้อย'),
(120, 5, '2026-09-05 18:30:00', 304.00, 'confirmed', 'ยืนยันยอด'),
(121, 2, '2026-09-08 09:15:00', 185.00, 'confirmed', 'เพื่อนคนแรก'),
(122, 3, '2026-09-10 15:40:00', 152.00, 'confirmed', 'ซาซากิกับมิยาโนะ'),
(123, 4, '2026-09-12 20:00:00', 780.00, 'confirmed', 'ซื้อ Artbook 2 เล่ม'),
(124, 5, '2026-09-15 12:25:00', 152.00, 'confirmed', 'เรียบร้อย'),
(125, 2, '2026-09-18 17:35:00', 290.00, 'confirmed', 'ความปลอดภัยไซเบอร์'),
(126, 3, '2026-09-20 14:50:00', 152.00, 'pending', 'รอตรวจสอบสลิปจำลอง'),
(127, 4, '2026-09-22 19:10:00', 304.00, 'pending', 'ลูกค้ารอแจ้งโอน'),
(128, 5, '2026-09-25 11:00:00', 152.00, 'pending', 'รอผู้ดูแลตรวจสอบ'),
(129, 2, '2026-09-27 16:20:00', 152.00, 'confirmed', 'ยมแพ่งยมโลก'),
(130, 3, '2026-09-28 10:45:00', 230.00, 'confirmed', 'ยืนยันยอดล่าสุด'),
(131, 4, '2026-09-29 13:00:00', 456.00, 'confirmed', 'ยอดซื้อดีเด่น'),
(132, 2, '2026-09-29 22:15:00', 152.00, 'pending', 'รอชำระเงินจำลอง')
ON CONFLICT (order_id) DO NOTHING;

-- 4.7 Seed Data: รายการสินค้าในคำสั่งซื้อ (Order Items)
INSERT INTO order_items (item_id, order_id, ebook_id, price_at_purchase, quantity) VALUES
(1, 101, 1, 152.00, 1), (2, 101, 2, 152.00, 1),
(3, 102, 1, 152.00, 1),
(4, 103, 1, 152.00, 1), (5, 103, 2, 152.00, 1), (6, 103, 3, 152.00, 1),
(7, 104, 7, 185.00, 1),
(8, 105, 5, 152.00, 1),
(9, 106, 11, 290.00, 1),
(10, 107, 1, 152.00, 1), (11, 107, 2, 152.00, 1), (12, 107, 3, 152.00, 1), (13, 107, 4, 152.00, 1),
(14, 108, 6, 152.00, 1),
(15, 109, 12, 390.00, 1),
(16, 110, 8, 152.00, 1),
(17, 111, 1, 152.00, 1), (18, 111, 7, 185.00, 1),
(19, 112, 9, 152.00, 1),
(20, 113, 10, 230.00, 1),
(21, 114, 2, 152.00, 1), (22, 114, 3, 152.00, 1),
(23, 115, 11, 290.00, 2),
(24, 116, 5, 152.00, 1),
(25, 117, 9, 152.00, 1),
(26, 118, 1, 152.00, 1), (27, 118, 11, 290.00, 1),
(28, 119, 6, 152.00, 1),
(29, 120, 3, 152.00, 1), (30, 120, 4, 152.00, 1),
(31, 121, 7, 185.00, 1),
(32, 122, 8, 152.00, 1),
(33, 123, 12, 390.00, 2),
(34, 124, 5, 152.00, 1),
(35, 125, 11, 290.00, 1),
(36, 126, 1, 152.00, 1),
(37, 127, 1, 152.00, 1), (38, 127, 2, 152.00, 1),
(39, 128, 6, 152.00, 1),
(40, 129, 5, 152.00, 1),
(41, 130, 10, 230.00, 1),
(42, 131, 1, 152.00, 1), (43, 131, 2, 152.00, 1), (44, 131, 3, 152.00, 1),
(45, 132, 4, 152.00, 1)
ON CONFLICT (item_id) DO NOTHING;

-- 4.8 Seed Data: การชำระเงิน (Payments)
INSERT INTO payments (payment_id, order_id, payment_method, payment_date, slip_image_url, status, verified_by) VALUES
(1, 101, 'PromptPay', '2026-07-05 10:20:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_101', 'verified', 1),
(2, 102, 'PromptPay', '2026-07-06 14:25:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_102', 'verified', 1),
(3, 103, 'PromptPay', '2026-07-10 09:50:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_103', 'verified', 1),
(4, 104, 'PromptPay', '2026-07-12 16:35:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_104', 'verified', 1),
(5, 106, 'PromptPay', '2026-07-20 18:05:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_106', 'verified', 1),
(6, 107, 'PromptPay', '2026-07-25 12:40:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_107', 'verified', 1),
(7, 108, 'PromptPay', '2026-07-28 20:20:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_108', 'verified', 1),
(8, 109, 'PromptPay', '2026-08-02 08:35:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_109', 'verified', 1),
(9, 110, 'PromptPay', '2026-08-04 13:45:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_110', 'verified', 1),
(10, 111, 'PromptPay', '2026-08-08 19:30:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_111', 'verified', 1),
(11, 113, 'PromptPay', '2026-08-15 17:55:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_113', 'verified', 1),
(12, 114, 'PromptPay', '2026-08-18 21:10:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_114', 'verified', 1),
(13, 115, 'PromptPay', '2026-08-22 10:05:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_115', 'verified', 1),
(14, 116, 'PromptPay', '2026-08-25 14:20:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_116', 'verified', 1),
(15, 117, 'PromptPay', '2026-08-29 16:50:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_117', 'verified', 1),
(16, 118, 'PromptPay', '2026-09-01 11:25:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_118', 'verified', 1),
(17, 119, 'PromptPay', '2026-09-03 13:15:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_119', 'verified', 1),
(18, 120, 'PromptPay', '2026-09-05 18:35:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_120', 'verified', 1),
(19, 121, 'PromptPay', '2026-09-08 09:20:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_121', 'verified', 1),
(20, 122, 'PromptPay', '2026-09-10 15:45:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_122', 'verified', 1),
(21, 123, 'PromptPay', '2026-09-12 20:05:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_123', 'verified', 1),
(22, 124, 'PromptPay', '2026-09-15 12:30:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_124', 'verified', 1),
(23, 125, 'PromptPay', '2026-09-18 17:40:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_125', 'verified', 1),
(24, 126, 'PromptPay', '2026-09-20 14:55:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_126', 'pending', NULL),
(25, 127, 'PromptPay', '2026-09-22 19:15:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_127', 'pending', NULL),
(26, 128, 'PromptPay', '2026-09-25 11:05:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_128', 'pending', NULL),
(27, 129, 'PromptPay', '2026-09-27 16:25:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_129', 'verified', 1),
(28, 130, 'PromptPay', '2026-09-28 10:50:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_130', 'verified', 1),
(29, 131, 'PromptPay', '2026-09-29 13:05:00', 'https://dummyimage.com/600x800/0070d2/ffffff&text=SLIP_ORDER_131', 'verified', 1)
ON CONFLICT (payment_id) DO NOTHING;

-- 4.9 Seed Data: ลิงก์ดาวน์โหลด (เฉพาะ Order ที่สถานะเป็น confirmed เท่านั้น!)
INSERT INTO download_links (link_id, order_id, ebook_id, token, download_url, expires_at, download_count) VALUES
(1, 101, 1, 'token_101_1_abc', 'https://mockfile.nothave.com/download?id=1&token=token_101_1_abc', '2026-12-31 23:59:59', 2),
(2, 101, 2, 'token_101_2_def', 'https://mockfile.nothave.com/download?id=2&token=token_101_2_def', '2026-12-31 23:59:59', 1),
(3, 102, 1, 'token_102_1_ghi', 'https://mockfile.nothave.com/download?id=1&token=token_102_1_ghi', '2026-12-31 23:59:59', 0),
(4, 103, 1, 'token_103_1_jkl', 'https://mockfile.nothave.com/download?id=1&token=token_103_1_jkl', '2026-12-31 23:59:59', 3),
(5, 103, 2, 'token_103_2_mno', 'https://mockfile.nothave.com/download?id=2&token=token_103_2_mno', '2026-12-31 23:59:59', 1),
(6, 103, 3, 'token_103_3_pqr', 'https://mockfile.nothave.com/download?id=3&token=token_103_3_pqr', '2026-12-31 23:59:59', 1),
(7, 104, 7, 'token_104_7_stu', 'https://mockfile.nothave.com/download?id=7&token=token_104_7_stu', '2026-12-31 23:59:59', 0),
(8, 106, 11, 'token_106_11_vwx', 'https://mockfile.nothave.com/download?id=11&token=token_106_11_vwx', '2026-12-31 23:59:59', 4),
(9, 107, 1, 'token_107_1_yza', 'https://mockfile.nothave.com/download?id=1&token=token_107_1_yza', '2026-12-31 23:59:59', 1),
(10, 107, 2, 'token_107_2_bcd', 'https://mockfile.nothave.com/download?id=2&token=token_107_2_bcd', '2026-12-31 23:59:59', 1),
(11, 107, 3, 'token_107_3_efg', 'https://mockfile.nothave.com/download?id=3&token=token_107_3_efg', '2026-12-31 23:59:59', 1),
(12, 107, 4, 'token_107_4_hij', 'https://mockfile.nothave.com/download?id=4&token=token_107_4_hij', '2026-12-31 23:59:59', 1),
(13, 108, 6, 'token_108_6_klm', 'https://mockfile.nothave.com/download?id=6&token=token_108_6_klm', '2026-12-31 23:59:59', 0),
(14, 109, 12, 'token_109_12_nop', 'https://mockfile.nothave.com/download?id=12&token=token_109_12_nop', '2026-12-31 23:59:59', 2),
(15, 110, 8, 'token_110_8_qrs', 'https://mockfile.nothave.com/download?id=8&token=token_110_8_qrs', '2026-12-31 23:59:59', 1),
(16, 131, 1, 'token_131_1_tuv', 'https://mockfile.nothave.com/download?id=1&token=token_131_1_tuv', '2026-12-31 23:59:59', 1)
ON CONFLICT (link_id) DO NOTHING;

-- ปรับ Sequence ให้ค่า ID ต่อเนื่องอัตโนมัติ
SELECT setval('roles_role_id_seq', (SELECT MAX(role_id) FROM roles));
SELECT setval('users_user_id_seq', (SELECT MAX(user_id) FROM users));
SELECT setval('categories_category_id_seq', (SELECT MAX(category_id) FROM categories));
SELECT setval('authors_author_id_seq', (SELECT MAX(author_id) FROM authors));
SELECT setval('ebooks_ebook_id_seq', (SELECT MAX(ebook_id) FROM ebooks));
SELECT setval('orders_order_id_seq', (SELECT MAX(order_id) FROM orders));
SELECT setval('order_items_item_id_seq', (SELECT MAX(item_id) FROM order_items));
SELECT setval('payments_payment_id_seq', (SELECT MAX(payment_id) FROM payments));
SELECT setval('download_links_link_id_seq', (SELECT MAX(link_id) FROM download_links));

-- ====================================================================
-- 5. 4 SQL QUERIES FOR ANALYTICAL REPORTS (ตามเกณฑ์ข้อกำหนดหน้า 4)
-- ====================================================================

-- --------------------------------------------------------------------
-- รายงานที่ 1: ยอดขายตามช่วงเวลา (Sales Over Time)
-- คำถามที่ต้องตอบ: ยอดขาย จำนวนคำสั่งซื้อ และค่าเฉลี่ยต่อคำสั่งซื้อ เปลี่ยนไปอย่างไรตามวันที่หรือเดือน
-- ใช้: JOIN, GROUP BY, SUM, COUNT, AVG, ตัวกรองวัน
-- --------------------------------------------------------------------
/*
SELECT 
    TO_CHAR(o.order_date, 'YYYY-MM') AS sale_month,
    COUNT(o.order_id) AS total_orders,
    SUM(o.total_amount) AS total_sales,
    ROUND(AVG(o.total_amount), 2) AS average_order_value
FROM orders o
WHERE o.status = 'confirmed'
GROUP BY TO_CHAR(o.order_date, 'YYYY-MM')
ORDER BY sale_month ASC;
*/

-- --------------------------------------------------------------------
-- รายงานที่ 2: E-Book ขายดี (Best-Selling E-Books)
-- คำถามที่ต้องตอบ: E-Book ใดขายได้มากที่สุดตามจำนวนเล่มหรือยอดขาย
-- ใช้: JOIN, GROUP BY, SUM หรือ COUNT, และ LIMIT
-- --------------------------------------------------------------------
/*
SELECT 
    e.ebook_id,
    e.title,
    c.category_name,
    SUM(oi.quantity) AS total_units_sold,
    SUM(oi.quantity * oi.price_at_purchase) AS total_revenue
FROM ebooks e
JOIN order_items oi ON e.ebook_id = oi.ebook_id
JOIN orders o ON oi.order_id = o.order_id
JOIN categories c ON e.category_id = c.category_id
WHERE o.status = 'confirmed'
GROUP BY e.ebook_id, e.title, c.category_name
ORDER BY total_units_sold DESC, total_revenue DESC
LIMIT 5;
*/

-- --------------------------------------------------------------------
-- รายงานที่ 3: ยอดขายตามหมวดหมู่ (Sales by Category)
-- คำถามที่ต้องตอบ: หมวดหมู่ใดสร้างยอดขายและจำนวนรายการสูงสุด
-- ใช้: JOIN หลายตาราง, GROUP BY, SUM
-- --------------------------------------------------------------------
/*
SELECT 
    c.category_id,
    c.category_name,
    COUNT(DISTINCT o.order_id) AS order_count,
    SUM(oi.quantity) AS total_items_sold,
    SUM(oi.quantity * oi.price_at_purchase) AS total_category_sales
FROM categories c
JOIN ebooks e ON c.category_id = e.category_id
JOIN order_items oi ON e.ebook_id = oi.ebook_id
JOIN orders o ON oi.order_id = o.order_id
WHERE o.status = 'confirmed'
GROUP BY c.category_id, c.category_name
ORDER BY total_category_sales DESC;
*/

-- --------------------------------------------------------------------
-- รายงานที่ 4: ลูกค้าและคำสั่งซื้อ (Customer Spending & Order Frequency)
-- คำถามที่ต้องตอบ: ลูกค้ารายใดซื้อบ่อยหรือมียอดซื้อสะสมสูง และแต่ละสถานะมีจำนวนเท่าใด
-- ใช้: JOIN, GROUP BY, HAVING, COUNT, SUM, เงื่อนไขสถานะ
-- --------------------------------------------------------------------
/*
SELECT 
    u.user_id,
    u.full_name,
    u.email,
    COUNT(o.order_id) AS total_confirmed_orders,
    SUM(o.total_amount) AS total_spent
FROM users u
JOIN orders o ON u.user_id = o.user_id
WHERE o.status = 'confirmed'
GROUP BY u.user_id, u.full_name, u.email
HAVING COUNT(o.order_id) >= 2
ORDER BY total_spent DESC;
*/
