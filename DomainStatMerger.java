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

import java.io.File;
import java.io.FileNotFoundException;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/**
 * Special purpose merger for CSV files from the
 * <a href="https://github.com/ymaurer/cdx-summarize-warc-indexer">CDX-summarise</a>} project.
 *
 * The CSV-files contains entries with domain name, year, count and bytes: {@code "1000steine.de",2019,6,43694}.
 * Domain name and year are kept as-is while count and bytes are summed for each unique domain+year combination.
 */
public class DomainStatMerger {

    public static void main(String[] args) throws IOException {
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

        run(csvs);
    }

    //"1000steine.de",2019,6,43694
    private static final Pattern ENTRY_PATTERN = Pattern.compile("^(\"[^\"]+\"),([0-9]{4}),([0-9]+),([0-9]+)$");

    public static void run(List<File> csvs) throws IOException {
        //System.err.println("Loading " + csvs.size() + " files into memory");
        ArrayList<String> raws = new ArrayList<>();
        for (File csv: csvs) {
            raws.addAll(Files.readAllLines(csv.toPath(), StandardCharsets.UTF_8));
        }

        //System.err.println("Loaded " + raws.size() + " lines. Sorting them...");
        Collections.sort(raws); // Natural order is fine

        //System.err.println("Sorting finished. Iterating and merging...");
        merge(raws);
    }

    private static void merge(ArrayList<String> raws) {
        String lastDomain = null;
        String lastYear = ""; // Only used as key, not as a number
        long countSum = 0L;
        long countBytes = 0L;
        for (String raw: raws) {
            if (raw.isEmpty()) {
                continue;
            }
            Matcher m = ENTRY_PATTERN.matcher(raw);
            if (!m.matches()) {
                System.err.println("Skipping entry as it is not recognized as valid: '" + raw + "'");
                continue;
            }
            if (!(m.group(1).equals(lastDomain) && m.group(2).equals(lastYear)) && lastDomain != null) {
                System.out.printf(Locale.ROOT, "%s,%s,%d,%d\n", lastDomain, lastYear, countSum, countBytes);
                countSum = 0L;
                countBytes = 0L;
            }
            lastDomain = m.group(1);
            lastYear = m.group(2);
            countSum += Long.parseLong(m.group(3));
            countBytes += Long.parseLong(m.group(4));
        }
        System.out.printf(Locale.ROOT, "%s,%s,%d,%d\n", lastDomain, lastYear, countSum, countBytes);
    }
}
