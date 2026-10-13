import Foundation

/// Very common first names, which speech models already spell and which Wispr Flow also leaves out of automatic learning.
enum CommonNames {
    static let all = Set("""
        aaron adam adrian aisha alan albert alex alexander alice alicia allison amanda amber amit amy ana andrea andrew angela
        anil anita ann anna anne anthony arjun arthur ashley barbara ben benjamin beth betty bill billy bob bobby brandon brenda
        brian bruce bryan carl carlos carol caroline catherine charles charlie cheryl chris christian christina christine
        christopher cindy claire craig crystal cynthia daniel danielle david deborah debra denise dennis diana diane donald
        donna doris dorothy douglas dylan edward elizabeth emily emma eric ethan eugene evelyn frances frank gabriel gary
        george gerald gloria grace greg gregory hannah harold harry heather helen henry isabella jack jacob james jane janet
        janice jason jean jeff jeffrey jennifer jeremy jerry jesse jessica jim joan joe john johnny jonathan jordan jose joseph
        joshua joyce juan judith judy julia julie justin karen katherine kathleen kathryn kathy keith kelly kenneth kevin
        kim kimberly kyle larry laura lauren lawrence linda lisa logan louis lucas luis madison margaret maria marie marilyn
        mark martha martin mary matt matthew megan melissa michael michelle mike nancy natalie nathan nicholas nicole noah
        olivia pamela patricia patrick paul peter philip priya rachel rahul raj ralph randy raymond rebecca richard rick
        robert roger ronald rose roy russell ruth ryan sam samantha samuel sandra sara sarah scott sean sharon shirley sophia
        stephanie stephen steve steven susan teresa terry thomas tim timothy tom tony tyler victoria vincent virginia walter
        wayne william zachary
        """.split(whereSeparator: \.isWhitespace).map(String.init))

    static func contains(_ word: String) -> Bool { all.contains(word.lowercased()) }
}
