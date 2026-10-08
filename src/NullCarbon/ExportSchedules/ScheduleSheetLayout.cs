namespace SCaddins.ExportSchedules
{
    using System;
    using System.Collections.Generic;
    using System.Linq;

    /// <summary>
    /// Puts an exported schedule into the worksheet layout the nullCarbon backend reads
    /// (pandas read_excel with header=[1]): row 1 is a title, row 2 the column headings,
    /// data from row 3.
    ///
    /// Revit's text export leaves out the title row when "Export Title" is off or the
    /// schedule hides its title, and the headings row when "Export Column Headers" is off
    /// or the schedule hides its headers. The backend then either fails ("Passed header=[1],
    /// len of 1, but only 1 lines in file") or silently reads the first data row as the
    /// headings. This class adds whichever of the two rows is missing and leaves an export
    /// that already has both exactly as Revit wrote it.
    /// </summary>
    public static class ScheduleSheetLayout
    {
        /// <param name="rows">Exported lines split into fields; a blank line is an empty list.</param>
        /// <param name="title">Text for an added title row (the schedule name).</param>
        /// <param name="headings">The schedule's visible column headings, in order.</param>
        /// <param name="titleExported">Revit was asked for the title and the schedule shows it.</param>
        /// <param name="headingsExported">Revit was asked for column headers and the schedule shows them.</param>
        /// <returns>The rows to write: title, headings, then the exported data rows.</returns>
        public static List<List<string>> Normalize(
            IEnumerable<List<string>> rows,
            string title,
            IList<string> headings,
            bool titleExported,
            bool headingsExported)
        {
            var result = rows.SkipWhile(IsBlank).ToList();

            if (result.Count == 0 || !IsTitleRow(result[0], title, titleExported))
            {
                result.Insert(0, new List<string> { title ?? string.Empty });
            }

            // A blank line between the title and the headings would become the backend's
            // header row, so drop any there; blank lines carry no data.
            while (result.Count > 1 && IsBlank(result[1]))
            {
                result.RemoveAt(1);
            }

            // With "grouped column headers" Revit writes several heading rows; trust them
            // when headers were exported, and only add our own row when they were not.
            bool hasHeadings = result.Count > 1 && (headingsExported || MatchesHeadings(result[1], headings));
            if (!hasHeadings)
            {
                result.Insert(1, new List<string>(headings));
            }

            return result;
        }

        private static bool IsTitleRow(List<string> row, string title, bool titleExported)
        {
            var filled = row.Where(field => !string.IsNullOrWhiteSpace(field)).ToList();
            if (filled.Count != 1)
            {
                return false;
            }

            // Revit's title row is a single cell. When the title was not expected, only
            // accept a single-cell row that is the schedule name, so a lone group-header
            // line such as "Level 1" is not mistaken for the title.
            return titleExported
                || string.Equals(filled[0].Trim(), (title ?? string.Empty).Trim(), StringComparison.OrdinalIgnoreCase);
        }

        private static bool MatchesHeadings(List<string> row, IList<string> headings)
        {
            var fields = TrimTrailingEmpty(row);
            var expected = TrimTrailingEmpty(headings);
            return expected.Count > 0
                && fields.Count == expected.Count
                && fields.Zip(expected, (a, b) => string.Equals(a, b, StringComparison.OrdinalIgnoreCase)).All(same => same);
        }

        private static List<string> TrimTrailingEmpty(IEnumerable<string> fields)
        {
            var trimmed = fields.Select(field => (field ?? string.Empty).Trim()).ToList();
            while (trimmed.Count > 0 && trimmed[trimmed.Count - 1].Length == 0)
            {
                trimmed.RemoveAt(trimmed.Count - 1);
            }

            return trimmed;
        }

        private static bool IsBlank(List<string> row)
        {
            return row == null || row.All(string.IsNullOrWhiteSpace);
        }
    }
}
