/*
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
 *
 */
package dk.ekot.misc;

import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStreamWriter;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Comparator;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.NoSuchElementException;
import java.util.PriorityQueue;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/**
 * Special purpose merger for CSV files from the
 * <a href="https://github.com/ymaurer/cdx-summarize-warc-indexer">CDX-summarise</a>} project.
 *
 * This works on multiple output files from {@link DomainStatMerger} (or similar files which have the same sorting order).
 *
 * The CSV-files contains entries with domain name, year, count and bytes: {@code "1000steine.de",2019,6,43694}.
 * The output follows https://github.com/ymaurer/cdx-summarize#summary-output-file-format with the sample
 * <pre>
 * bnl.lu {"2001":{"n_audio":0,"n_css":0,"n_font":0,"n_html":31,"n_http":31,"n_https":0,"n_image":0,"n_js":0,"n_json":0,"n_other":0,"n_pdf":0,"n_total":31,"n_video":0,"s_audio":0,"s_css":0,"s_font":0,"s_html":9323,"s_http":9323,"s_https":0,"s_image":0,"s_js":0,"s_json":0,"s_other":0,"s_pdf":0,"s_total":9323,"s_video":0},
"2002":{"n_audio":0,"n_css":0,"n_font":0,"n_html":175,"n_http":175,"n_https":0,"n_image":0,"n_js":0,"n_json":0,"n_other":0,"n_pdf":0,"n_total":175,"n_video":0,"s_audio":0,"s_css":0,"s_font":0,"s_html":52634,"s_http":52634,"s_https":0,"s_image":0,"s_js":0,"s_json":0,"s_other":0,"s_pdf":0,"s_total":52634,"s_video":0},
"2003":{"n_audio":0,"n_css":8,"n_font":0,"n_html":639,"n_http":728,"n_https":0,"n_image":44,"n_js":0,"n_json":0,"n_other":7,"n_pdf":30,"n_total":728,"n_video":0,"s_audio":0,"s_css":5268,"s_font":0,"s_html":1295481,"s_http":4680354,"s_https":0,"s_image":295235,"s_js":0,"s_json":0,"s_other":13156,"s_pdf":3071214,"s_total":4680354,"s_video":0}}
 * </pre>
 * Note that it is single-line for each domain, akin to the JSON-Lines format.
 */
public class DomainStatJSON {

    public static void main(String[] args) {
        if (args.length == 0) {
            System.out.println("Usage: DomainStatsMerger csv+");
            System.exit(2);
        }

        List<File> csvs = Arrays.stream(args).
                map(File::new).
                peek(f -> {
                    if (!f.exists()) {
                        throw new RuntimeException(new FileNotFoundException("Unable to locate '" + f + "'"));
                    }
                }).
                collect(Collectors.toList());
        new DomainStatJSON(csvs);
    }

    /**
     * Prepares for export by lazy-loading the CSVs.
     */
    public DomainStatJSON(List<File> csvs) {
        //System.out.println("Lazy loading " + csvs.size() + " pre-sorted CSV files");
        List<DomainBag> sources = sources = csvs.stream().
            // ensureOrdered is not needed in the standard case where DomainStatsMerger has delivered the files
            //                map(this::ensureOrdered).
                map(DomainBag::new).
                collect(Collectors.toList());
        extract(sources);
    }

    /**
     * Loads all lines from the given strFile and sorts them naturally.
     * If this operation changes the order, the sorted files are stored in a new file and a pointer to
     * the new file is returned. If the order is unchanged, the original strFile is returned.
     * @return strFile or a new file, either way garanteeing natural order of lines.
     */
    public File ensureOrdered(File strFile) {
        List<String> originalLines;
        try {
            originalLines = Files.readAllLines(strFile.toPath(), StandardCharsets.UTF_8);
        } catch (Exception e) {
            throw new RuntimeException("Exception reading '" + strFile + "'", e);
        }
        List<String> sortedLines = new ArrayList<>(originalLines);
        sortedLines.sort(String::compareTo);
        boolean equal = true;
        for (int i = 0 ; i < originalLines.size() ; i++) {
            if (!originalLines.get(i).equals(sortedLines.get(i))) {
                equal = false;
                break;
            }
        }
        if (equal) {
            return strFile;
        }

        originalLines = null; // Not needed anymore
        File sortedFile = new File(strFile.toString() + ".sorted");
        if (!sortedFile.exists()) {
            try (FileOutputStream out = new FileOutputStream(sortedFile);
                 BufferedOutputStream bout = new BufferedOutputStream(out);
                 OutputStreamWriter os = new OutputStreamWriter(bout, StandardCharsets.UTF_8)) {
                os.write(sortedLines.stream().collect(Collectors.joining("\n")));
            } catch (Exception e) {
                throw new RuntimeException("Exception sorting '" + strFile + "'", e);
            }
        }
        return sortedFile;
    }

    /**
     * Produces JSON-Lines output by String hacking instead of a proper framework.
     * This is to avoid third party dependencies.
     */
    private static void extract(List<DomainBag> sources) {
        PriorityQueue<DomainBag> pq = new PriorityQueue<>(sources);

        String lastDomain = null;
        String lastYear = null;
        while (!pq.isEmpty() && !pq.peek().isEmpty()) {
            Entry mainEntry = pq.peek().peek();

//            System.out.println("\n*** All: " + sources.stream().map(DomainBag::toString).collect(Collectors.joining(", ")) +
//                               " main: " + mainEntry);

            if (mainEntry.domain.equals(lastDomain) && mainEntry.year.equals(lastYear)) { // Already handled: Skip it
                DomainBag mainBag = pq.poll();
                mainBag.pop(); // Same as mainEntry
                pq.add(mainBag); // Re-insert takes care of re-ordering of bags
                continue;
            }

            if (!mainEntry.domain.equals(lastDomain)) { // Whole new domain
                if (lastDomain != null) { // End-curlybrace + newline to start new entry, except for first entry
                    System.out.println("}");
                }
                System.out.printf(Locale.ROOT, "%s {", mainEntry.domain); // foo.dk
                lastDomain = mainEntry.domain;
                lastYear = null;
            }


            if (lastYear != null) {
                // Newline to start new entry, except for first entry
                System.out.print(", ");
            }
            lastYear = mainEntry.year;

            // TODO: Also check if domain is the same
            String counts = sources.stream().
                    map(DomainBag::safePeek).
                    // "n_audio":0 if the domain and year does not match, else
                    map(entry -> String.format(Locale.ROOT, "\"n_%s\":%d",
                                               entry.mime, entry.equalsDomainYear(mainEntry) ? entry.count : 0)).
                    collect(Collectors.joining(","));
            String bytes = sources.stream().
                    map(DomainBag::safePeek).
                    // "n_audio":0 if the domain and year does not match, else
                    map(entry -> String.format(Locale.ROOT, "\"s_%s\":%d",
                                               entry.mime, entry.equalsDomainYear(mainEntry) ? entry.bytes : 0)).
                    collect(Collectors.joining(","));
            System.out.printf(Locale.ROOT, "\"%s\": {%s,%s}", mainEntry.year, counts, bytes);

            DomainBag mainBag = pq.poll();
            mainBag.pop(); // Same as mainEntry
            pq.add(mainBag); // Re-insert takes care of re-ordering of bags
        }
    }

    /**
     * A single entry (domain, year, count, bytes) from a CSV file.
     */
    private static class Entry implements Comparable<Entry> {
        //"1000steine.de",2019,6,43694
        static final Pattern ENTRY_PATTERN = Pattern.compile("^\"([^\"]+)\",([0-9]{4}),([0-9]+),([0-9]+)$");

        public final String mime;
        public final String domain;
        public final String year;
        public final long count;
        public final long bytes;

        private final Comparator<Entry> comparator = Comparator.
                comparing(Entry::getDomain).
                thenComparing(Entry::getYear).
                thenComparingLong(Entry::getCount).
                thenComparingLong(Entry::getBytes);

        // Empty entry
        public Entry(String mime) {
            this.mime = mime;
            domain = "";
            year = "";
            count = 0;
            bytes = 0;
        }
        public Entry(String mime, String csvEntry) {
            this.mime = mime;
            Matcher m = ENTRY_PATTERN.matcher(csvEntry);
            if (!m.matches()) {
                throw new IllegalArgumentException("Unable to parse line '" + csvEntry +
                                                   "' as it does not match pattern '" + ENTRY_PATTERN.pattern() + "'");
            }
            domain = m.group(1);
            year = m.group(2);
            count = Long.parseLong(m.group(3));
            bytes = Long.parseLong(m.group(4));
        }

        /**
         * Ignores {@link #mime}, orders by {@link #domain}, {@link #year}, {@link #count}, {@link #bytes}.
         */
        @Override
        public int compareTo(Entry other) {
            return comparator.compare(this, other);
        }

        public boolean equalsDomainYear(Entry other) {
            return domain.equals(other.getDomain()) && year.equals(other.getYear());
        }

        public String getMime() {
            return mime;
        }

        public String getDomain() {
            return domain;
        }

        public String getYear() {
            return year;
        }

        public long getCount() {
            return count;
        }

        public long getBytes() {
            return bytes;
        }


        @Override
        public String toString() {
            return "{" +
                   "domain='" + domain + '\'' +
                   ", year='" + year + '\'' +
                   ", mime='" + mime + '\'' +
                   ", count=" + count +
                   ", bytes=" + bytes +
                   '}';
        }
    }

    /**
     * Holds a list of strings, providing methods for loading from file and popping string in deterministic order.
     */
    private static class DomainBag implements Comparable<DomainBag> {
        static final Pattern MIME_PATTERN = Pattern.compile(".*_([a-zA-Z]*)-result.*");

        private final Iterator<String> lines;
        private final String mime; // Okay, not mime, but heavilyNormalisedFileType is a bit long
        private Entry top;
        private final Entry EMPTY;

        public DomainBag(File source)  {
            try {
                Matcher m = MIME_PATTERN.matcher(source.getName());
                if (!m.matches()) {
                    throw new IllegalArgumentException(
                            "Unable to extract MIME for filename '" + source + "'. Expected input such as " +
                            "'.../q_video-result.csv' where the MIME would be 'video' based on the regexp '" +
                            MIME_PATTERN.pattern() + "'");
                }
                mime = m.group(1);
                EMPTY = new Entry(mime);
                lines = Files.lines(source.toPath(), StandardCharsets.UTF_8).iterator();
            } catch (IOException e) {
                throw new RuntimeException("Unable to read strings from '" + source + "'", e);
            }
            top = lines.hasNext() ? new Entry(mime, lines.next()) : null;
        }

        /**
         * Removes the next element from the list and returns it.
         * @return the next element in the ordered list.
         */
        public Entry pop() {
            if (isEmpty()) {
                throw new NoSuchElementException("The bag is empty");
            }
            Entry old = top;
            top = lines.hasNext() ? new Entry(mime, lines.next()) : null;
            return old;
        }

        /**
         * Reads the next element from the list and returns it without changing the list.
         * @return the next element in the ordered list.
         */
        public Entry peek() {
            if (isEmpty()) {
                throw new NoSuchElementException("The bag is empty");
            }
            return top;
        }

        /**
         * Reads the next element from the list and returns it without changing the list.
         * If there are no more elements, {@link #EMPTY} is returned.
         * @return the next element in the ordered list.
         */
        public Entry safePeek() {
            if (isEmpty()) {
                return EMPTY;
            }
            return top;
        }

        public String getMime() {
            return mime;
        }

        /**
         * @return true if there are no more elements.
         */
        public boolean isEmpty() {
            return top == null;
        }

        /**
         * @return true is there are at least one more element.
         */
        public boolean hasContent() {
            return !isEmpty();
        }

        @Override
        public int compareTo(DomainBag other) {
            if (isEmpty()) {
                return other.isEmpty() ? 0 : 1;
            }
            if (other.isEmpty()) {
                return 1;
            }
            return peek().compareTo(other.peek());
        }

        @Override
        public String toString() {
            return "DB(top=" + safePeek().toString() + ")";
        }
    }
}
