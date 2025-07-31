
# /// script
# dependencies = [
#   "pyodbc",
#   "tabulate",
#   "tqdm",
#   "xlwings",
# ]
# ///

from argparse import ArgumentParser
from fractions import Fraction
import csv
import os
import re
from types import SimpleNamespace

CONE_BOM = re.compile(r"ConeBOM_\d{7}[A-Z]\d{2}(?:[-_]\w+)?\.ready")
CONE_MAT = re.compile(r"ConeMAT_\d{7}[A-Z]\d{2}(?:[-_]\w+)?\.ready")
MM = re.compile(r"\d{7}[A-Z]-MM(?:[-_]\w+)?\.ready")
STOCK_MM = re.compile(r"((?:9-)?)((?:HPS)?(?:5|7|10)0(?:\/50)?W?(?:[TF][123])?)-(\d{2})(\d{2})([\w-]*)")
PROJ_MM = re.compile(r"(\d{7}[A-Z]\d{0,2})-([012])(\d{4})(\w*)")
GRADE = re.compile(r"([AM]\d{3})-(3\d{2}|TYPE\s?4|(?:HPS)?[5710]{1,2}0W?)((?:[TF][123])?)")
DESC_PATTERN = re.compile(r"PL ([\d\/\s]+) x ([\d\/\s]+) x ([\d'-]+)\s?((?:A709|M270)-)?((?:HPS)?[1057]0W?(?:[TF][123])?)?")

CONVERTED_MM = re.compile(r"\d{7}[A-Z]\d{0,2}-[789]\d{4}\w*")
WEB_MM = re.compile(r"\d{7}[A-Z]\d{0,2}-[09]3\d{3}\w*")
FLG_MM = re.compile(r"\d{7}[A-Z]\d{0,2}-[09]4\d{3}\w*")
WEB_PART = re.compile(r"\d{5,7}[A-Z]\d{0,2}-?[A-Z]{1,3}\d+[A-Z]*-?[NF]?W\d+")
FLG_PART = re.compile(r"\d{5,7}[A-Z]\d{0,2}-?[A-Z]{1,3}\d+[A-Z]*-?[TB]\d+")
ANY_PART = re.compile(r"(\d{7}[A-Z])\d{0,2}-([\w-]+)")
TRUNCATE_PART = re.compile(r"1(\d{2})0(\d{3}[A-Z]\d{0,2})-(\w+)-?(\w*)")

FOLDER = "conversion"
CONVERT_DESC = False

part_grades = dict()

def tsv_wrapper(func):
    def wrapper(self, line):
        if type(line) is str:
            line = line.replace("\n", "").split("\t")
        line = func(self, line)
        if line:
            line = map(str, [s or '' for s in line])
            return "\t".join(line)
        return ''

    return wrapper

def parse_grade(grade):
    match = GRADE.match(grade)
    if match:
        spec, grade, test = match.groups()

        if spec == 'A240':
            grade = f'TYPE {grade}'

        if (spec, grade) == ('A606', 'TYPE4'):
            spec = 'A606TYPE4'
            grade = None

        return [spec, grade, test]

    return None, None, None

def parse_desc(desc):
    match = DESC_PATTERN.match(desc)
    if match:
        thk, width, length, spec, grade =  match.groups()

        inches = 0
        if ' ' in thk:
            a,b = thk.split(' ', 1)
            thk = float(a) + Fraction(b)
        elif '/' in thk:
            thk = Fraction(thk)

        if ' ' in width:
            a,b = width.split(' ', 2)
            width = float(int(a) + Fraction(b))

        if "'-" in length:
            feet, inches = length.split("'-", 1)
            length = feet * 12 + inches

        return {
            'Thickness': float(thk),
            'Width': float(width),
            'Length': float(length),
            'Grade': "{}{}".format(spec or "A709-", grade)
        }
    return None

def fmt_inches(val: str | float | int):
    """
    Format inches value as a string with fraction part.
    - '1.0' -> '1'
    - '0.500' -> '1/2'
    - '1.25' -> '1 1/4'
    """
    num = float(val)
    inches = int(num)
    frac = Fraction(num - inches).limit_denominator(32)

    return "{} {}".format(inches or "", frac or "").strip() or "0"

class ReadyFile(object):
    def __init__(self, file_name="default.ready"):
        self.file_name = file_name

        self.lines = []
        self.converted = []

    @staticmethod
    def matches_filename(file_name) -> bool:
        return False

    def infer_process(self, file_name=None):
        if file_name:
            self.file_name = file_name

        variants = [ConeBOM, ConeMAT, ProjMM]
        for Variant in variants:
            if Variant.matches_filename(self.file_name):
                Variant(self.file_name).convert()
                break
        else:
            raise ValueError("No valid variant found for filename `{}`".format(self.file_name))

    def has_header(self) -> bool:
        return False

    def convert(self):
        assert self.file_name is not None, "File name is not set"

        with open(os.path.join(FOLDER, 'input', self.file_name), "r") as file:
            self.lines = file.readlines()

        self.process()

    def write_file(self, filename=None):
        if filename is None:
            filename = os.path.join(FOLDER, 'output', self.file_name)

        if len(self.converted) == 0:
            print("No lines to write for {}".format(self.file_name))
            return

        with open(filename, "w") as file:
            file.write("\n".join(self.converted))

        print("Converted {} lines in {}".format(len(self.converted), self.file_name))
        self.converted.clear()

    def process(self, data=None, name=None):
        if data:
            self.lines = data

        rows = iter(self.lines)
        if self.has_header():
            self.converted.append(self.convert_header(next(rows)))

        for line in rows:
            converted_line = self.convert_line(line)
            if converted_line:
                self.converted.append(converted_line)

        self.write_file(name)

    @tsv_wrapper
    def convert_header(self, line):
        return line

    @tsv_wrapper
    def convert_line(self, line):
        return line

    def fix_raw_mm(self, mm):
        match = PROJ_MM.match(mm)
        if match:
            job, prefix, item, suffix = match.groups()
            prefix = 9 - int(prefix)
            return "{}-{}{}{}".format(job, prefix, item, suffix)

        match = STOCK_MM.match(mm)
        if match:
            prefix, grade, inches, frac, suffix = match.groups()

            if grade == "50/50W":
                grade = "50/50WT2"

            inches = int(inches) + float(frac) / 16
            return "{}{}-P{:.4f}{}".format(prefix, grade, inches, suffix)

        return mm

class ConeBOM(ReadyFile):
    """
    modifications:
        - RawMM to new MM
            - Project: Prepend 9 to item
            - Stock: new-new stock
        - convert IN2 to FT2
        - ignore(remove) linear unit rows
    """

    @staticmethod
    def matches_filename(file_name):
        return bool(CONE_BOM.match(file_name))

    @tsv_wrapper
    def convert_line(self, line):
        if line[3] not in ["IN2", "FT2"]:
            return None

        line[1] = self.fix_raw_mm(line[1])
        if line[3] == "IN2":
            line[2] = str(round(float(line[2]) / 144.0, 3))
            line[3] = "FT2"


        return line

class ConeMAT(ReadyFile):
    """
    modifications:
        - add 3 columns for spec, grade, and test (split from grade earlier)
        - RawMM to new MM
            - Project: Prepend 9 to item
            - Stock: new-new stock
        - convert IN2 to FT2
        - generate new description
    """

    @staticmethod
    def matches_filename(file_name):
        return bool(CONE_MAT.match(file_name))

    @tsv_wrapper
    def convert_line(self, line):
        # only RawWeb, RawFlange or RawDetail
        if line[2] not in ["RawWeb", "RawFlange", "RawDetail"]:
            return None

        while len(line) < 15:
            line.append(None)

        line[12:] = parse_grade(line[8])
        if line[12] == 'A606TYPE4':
            line[8] = 'A606 TYPE 4'

        line[0] = self.fix_raw_mm(line[0])


        if line[7] == "IN2":
            # convert to FT2
            # line[6] = str(round(float(line[5]) * 40.8333, 3))
            line[6] = str(round(float(line[6]) * 144, 3))
            line[7] = 'FT2'

        # generate description to match new format
        if CONVERT_DESC:
            length, wid, thk = [fmt_inches(x) for x in line[3:6]]
            grade, test = line[-2:]
            if line[1].startswith("PL"):
                prefix = f"PL {thk}"
            else:
                prefix = line[1].split(' x ')[0]
            line[1] = f"{prefix} x {wid} x {length} {grade}{test}"

        return line

class ProjMM(ReadyFile):
    """
    this file has a header
    modifications:
        - only rows of type WEB, FLANGE, or Part
        - add 5 columns (Spec, Grade, Test, Assembly Method, DocNo)
        - move Document to DocNo
        - Put PartName in Document
        - Parse Spec,Grade,Test from Nothing
    """

    POSSIBLE_ADDITIONS = ["SPEC", "GRADE", "TEST", "ASSYMETHOD", "DOCNO"]
    ORIGINAL_HEADER_LEN = 17
    HEADER_LEN = ORIGINAL_HEADER_LEN + len(POSSIBLE_ADDITIONS)

    @staticmethod
    def matches_filename(file_name):
        return bool(MM.match(file_name))

    def has_header(self):
        return True

    @tsv_wrapper
    def convert_header(self, line):
        return line + self.POSSIBLE_ADDITIONS[len(line)-self.ORIGINAL_HEADER_LEN:]

    @tsv_wrapper
    def convert_line(self, line):
        if line[0] not in ["WEB", "FLANGE", "PART"]:
            return None

        while len(line) < self.HEADER_LEN:
            line.append(None)

        line[-1] = line[12] # move DwgNo

        any_match = ANY_PART.match(line[1])
        if any_match:
            job, mark = any_match.groups()
            line[12] = f"{job}_{mark}"  # copy PartName

            # get Spec, Grade, Test
            line[17:20] = part_grades.setdefault(f"{job}-{mark}", [None] * 3)


        # generate description to match new format
        if CONVERT_DESC:
            length, wid, thk = [fmt_inches(x) for x in line[8:11]]
            spec, grade, test = line[17:20]
            grade_test = f"{grade or ''}{test or ''}"

            if line[2] and line[2].startswith("PL"):
                prefix = f"PL {thk}"
            else:
                prefix = line[2].split(' x ')[0]
            line[2] = f"{prefix} x {wid} x {length} {grade_test}".strip()

        return line

class ZFileParser(object):
    """
    Base class for ZHPP009 and ZHMM002 parsers.
    Provides a common interface for parsing and generating files.
    """

    def __init__(self):
        self.reset()

    def reset(self):
        self.h = SimpleNamespace()

    def parse_header(self, sheet):
        """
        Parse the header of the Excel sheet.
        This method should be overridden by subclasses.
        """
        raise NotImplementedError("Subclasses must implement parse_header method.")

    def parse_row(self, row):
        """
        Parse a single row of the Excel sheet.
        This method should be overridden by subclasses.
        """
        namespace = SimpleNamespace()

        for k, v in self.h.__dict__.items():
            setattr(namespace, k, row[v])

        return namespace

    def rows(self, sheet):
        """
        Generate rows from the Excel sheet.
        This method should be overridden by subclasses.
        """
        self.parse_header(sheet)

        end = max(self.h.__dict__.values()) + 1
        for row in sheet.range((2,1), (2, end)).expand("down").value:
            yield self.parse_row(row)

    def write_ready_file(self, filename, lines):
        text = "\n".join("\t".join(map(str, line)) for line in lines)
        with open(os.path.join(FOLDER, 'input', filename), "w") as file:
            file.write(text)
        print(f"Generated {len(lines)} lines for {filename} in input folder.")

class ZHPP009Parser(ZFileParser):
    """
    This class is used to parse ZHPP009 files.
    generates lines that pass the test:
        - UoM is IN2 or FT2
    """

    def reset(self):
        super().reset()
        self.bom = list()

    def matches_filename(self, workbook):
        return re.search(r"zhpp0*9", workbook.name.upper(), flags=re.IGNORECASE) is not None

    def parse_header(self, sheet):
        header = sheet.range("A1").expand("right").value
        self.h.matl = header.index("Material")
        self.h.raw_mm = header.index("Component")
        self.h.area = header.index("Quantity")
        self.h.unit = header.index("Un")
        self.h.scrap = header.index("C.scrap")

    def generate_row(self, row):
        self.bom.append([
            row.matl,    # PartName
            row.raw_mm,  # RawMM
            row.area,    # Area
            row.unit,    # UoM
            "", "", "",   # placeholders
            row.scrap    # Scrap
        ])

    def export(self, basename):
        if self.bom:
            name = f"{basename}_BOM.ready"
            # self.write_ready_file(name, self.bom)
            ConeBOM(name).process(self.bom, name)

    def generate_from_xl(self, workbook):
        """
        Generate a ConeBOM file from a ZHPP009 export Excel file.
        """

        exported = [None, ""]
        # format: PartName, RawMM, Area, UoM, <blank>, <blank>, <blank>, Scrap
        sheet = workbook.sheets.active
        for row in self.rows(sheet):
            if row.matl in exported:
                continue
            if row.unit not in ("IN2", "FT2"):
                continue

            self.generate_row(row)
            exported.append(row.matl)

        self.export(os.path.splitext(workbook.fullname)[0])
        self.reset()  # Reset for next file

class ZHMM002Parser(ZFileParser):
    """
    This class is used to parse ZHMM002 files.
    Project MM files are generated for lines that pass the test:
        - UoM is EA
        - Material Type is HALB
        - Material Description starts with PL, MISC, or SHEET
        - Line does not appear to be converted (Document is not a PartName)
    Cone MAT files are generated for lines that pass the test:
        - UoM is IN2 or FT2
        - Material Type is ZROH
        - Material Description starts with PL, MISC, or SHEET
    """

    def reset(self):
        super().reset()
        self.skipped = dict()
        self.exported = list()
        self.mm = list()
        self.mat = list()

        self.mm.append("PARTTYPE	MM	DESCRIPTION	UOM	WEIGHT	ALTDIM	ALTUOM	VOLUME	LENGTH	WIDTH	HEIGHT	ROUTING	DOCUMENT	PURCHTEXT	DOCNAME	DOCPATH	INDUSTRYSTD	SPEC	GRADE	TEST	ASSYMETHOD	DOCNO".split("\t"))


    def matches_filename(self, workbook):
        return re.search(r"zhmm0*2", workbook.name.upper(), flags=re.IGNORECASE) is not None

    def parse_header(self, sheet):
        header = sheet.range("A1").expand("right").value
        self.h.matl = header.index("Material")
        self.h.desc = header.index("Material Description")
        self.h.matl_type = header.index("MTyp")
        self.h.size = header.index("Size/dimensions")
        self.h.grade = header.index("Industry Std Desc.")
        self.h.uom = header.index("BUn")
        self.h.pdt = header.index("PDT")
        self.h.weight = header.index("Gross Weight")
        self.h.doc = header.index("Document")

    def parse_size(self, row):
        if not row.size:
            x = parse_desc(row.desc)
            return [x["Length"], x["Width"], x["Thickness"]]

        thk,wid,len = map(lambda x: round(float(x), 3), row.size.upper().split(' X '))

        return [len, wid, thk]

    def generate_mm(self, row):
        assert row.uom == "EA", "UoM is not EA"

        part_type = "PART"
        if WEB_PART.match(row.matl):
            part_type = "WEB"
        elif FLG_PART.match(row.matl):
            part_type = "FLANGE"

        self.mm.append([
            part_type,  # PartType
            row.matl,  # MM
            row.desc,  # Description
            row.uom,  # UOM
            row.weight,  # Weight
            "",  # AltDim
            "",  # AltUOM
            "",  # Volume
            *self.parse_size(row),  # Length, Width, Height
            "HS PARTS",  # Routing
            "",  # Document (will be moved later)
            "",  # PurchText
            row.doc,  # DocName
            "",  # DocPath
            row.grade,  # IndustryStd
        ])

    def generate_mat(self, row):
        if row.uom not in ("IN2", "FT2"):
            return None

        _type = "RawDetail"
        if WEB_MM.match(row.matl):
            _type = "RawWeb"
        elif FLG_MM.match(row.matl):
            _type = "RawFlange"

        self.mat.append([
            row.matl,  # RawMM
            row.desc,  # Description
            _type,  # Type
            *self.parse_size(row),  # Length, Width, Thickness
            row.weight,  # UnitWeight in FT2
            row.uom,  # UoM
            row.grade,  # Grade
            104152,  # Vendor (hardcoded)
            "",  # Price
            row.pdt,  # DeliveryTime
        ])

    def generate_row(self, row):
        match row.matl_type:
            case "HALB":
                self.generate_mm(row)
            case "ZROH":
                self.generate_mat(row)
            case _:
                return

        self.exported.append(row.matl)

    def export(self, basename):
        # Project MM
        if len(self.mm) > 1:
            name = f"{basename}_MM.ready"
            # self.write_ready_file(name, self.mm)
            ProjMM(name).process(self.mm, name)

        # Cone MAT
        if self.mat:
            name = f"{basename}_MAT.ready"
            # self.write_ready_file(name, self.mat)
            ConeMAT(name).process(self.mat, name)

    def generate_from_xl(self, workbook):
        """
        Generate a ZHMM002 file from a ZHMM002 export Excel file.
        """

        sheet = workbook.sheets.active
        for row in self.rows(sheet):
            if row.desc.split(' ')[0].upper() not in ('PL', 'MISC', 'SHEET', 'SHT', '10GA', '16GA'):
                continue

            if CONVERTED_MM.match(row.matl):
                print(f"skipping already converted mm {row.matl}")
                continue

            if row.matl in self.exported:
                continue

            self.generate_row(row)

        for mm, row in self.skipped.items():
            if mm not in self.exported:
                self.generate_row(row)  # process skipped rows

        self.export(os.path.splitext(workbook.fullname)[0])
        self.reset()


def main():
    parser = ArgumentParser()
    parser.add_argument("--gen-parts-grades", action="store_true", help="Generate part grades")
    parser.add_argument("--gen-bom-files", action="store_true", help="generate BOM files from SAP export")
    parser.add_argument("--gen-desc", action="store_true", help="generate descriptions in ConeMAT files")
    parser.add_argument("--min-project", type=int, default=0, help="Floor for filtering projects")
    parser.add_argument("-c", "--close", action="store_true", help="close workbook when complete")
    args = parser.parse_args()

    global CONVERT_DESC
    CONVERT_DESC = args.gen_desc

    if args.min_project:
        args.min_project = int(str(args.min_project).ljust(7, '0'))
        print("Min project:", args.min_project)

    if args.gen_parts_grades:
        generate_part_grades(floor=args.min_project)
        return

    part_grades.update(load_bom_parts())
    if args.gen_bom_files:
        generate_bom_files(args.close)
        return

    converter = ReadyFile()
    for f in os.listdir(os.path.join(FOLDER, "input")):
        converter.infer_process(f)


def generate_bom_files(close=False):
    import xlwings

    parsers = [ZHPP009Parser(), ZHMM002Parser()]
    for wb in xlwings.books:
        matched = False
        for parser in parsers:
            if parser.matches_filename(wb):
                try:
                    parser.generate_from_xl(wb)
                except Exception as e:
                    print(f"Error parsing file {wb.name}")
                    raise e
                matched = True
        if not matched:
            print(f"No parser found for workbook {wb.name}")

        elif close:
            wb.close()


def generate_part_grades(floor=0):
    import pyodbc
    from tqdm import tqdm

    conn = pyodbc.connect("DRIVER={};SERVER=HSSSQLSERV;Trusted_connection=yes;".format(pyodbc.drivers()[0]))
    cursor = conn.cursor()

    # get structid
    cursor.execute("EXEC BOM.SAP.GetEngStructures")
    jobs = list((line.Structure, line.StructID) for line in cursor.fetchall() if int(line.Project) >= floor)

    # get shipments
    progress = tqdm(jobs, desc="Reading Job BOMs")
    for job, structid in progress:
        cursor.execute("EXEC BOM.SAP.GetEngShipments @StructID=?", structid)
        shipments = list(line.ShipNo for line in cursor.fetchall())

        for ship in tqdm(shipments, desc="Reading Shipments for {}".format(job), position=1, leave=False):
            try:
                cursor.execute("EXEC BOM.SAP.GetBOMData @Job=?, @Ship=?", job, ship)
                for line in cursor.fetchall():
                    if line.Commodity not in ["PL", "MISC", "SHEET"]:
                        continue

                    mark = f"{job}-{line.Piecemark}".upper()
                    spec = line.Specification
                    grade = line.Grade
                    test = line.ImpactTest
                    if spec == 'A606 Type 4':
                        part_grades[mark] = ['A606', 'TYPE4', None]
                        continue

                    if test == "FCM":
                        test = "F"

                    if test and grade.startswith("HPS"):
                        test += '3'
                    elif test:
                        test += '2'
                    part_grades[mark] = [spec, grade, test]
                    # else:
                    #     print("Grade not parsed:", line.Grade)
            except Exception as e:
                progress.write(f"Error fetching BOM data for job {job} and ship {ship} ({structid}): {e}")

    cursor.close()

    with open("part_grades.csv", "w", newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['Mark', 'Specification', 'Grade', 'ImpactTest'])
        for mark, data in part_grades.items():
            writer.writerow([mark] + data)

def load_bom_parts():
    with open("part_grades.csv", "r") as f:
        reader = csv.reader(f)
        next(reader)  # Skip header
        return {row[0]: row[1:] for row in reader}

if __name__ == "__main__":
    main()
